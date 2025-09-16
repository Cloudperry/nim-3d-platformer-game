import std/[os, strformat, options, math]

import pkg/[glm, glfw]
from pkg/glfw/wrapper import `rawMouseMotionSupported`
import ./glad/gl
import GlUtils, Slangc

type
  ColoredVertex = object
    pos, color: Vec3f
  # Packed pragma might be necessary or more correct for structs passed to GPU?
  Uniforms = object
    mvp: Mat4f
  Transform = object
    pos: Vec3f
    scale: Vec3f = vec3f(1.0, 1.0, 1.0)
    rotation: Vec3f
  ProjectionKind = enum
    Orthographic, Perspective
  FpCameraOptions = object
    pitch, yaw, sensitivity, speed: float
  # TODO: Focal length sensitivity scaling for intuitive feeling sensitivity while scoping/changing FOV
  Camera = object
    pos: Vec3f
    yaw: GLfloat = PI/2 # Start the camera looking forward (toward -Z)
    pitch: GLfloat
    viewMat, projectionMat: Mat4f
    aspectRatio, nearClip, farClip: GLfloat
    case kind: ProjectionKind
    of Orthographic:
      frustumScale: GLfloat
    of Perspective:
      verticalFov: GLfloat

const
  degToRad = PI / 180
  camOptions = FpCameraOptions(pitch: 0.022 * degToRad, yaw: 0.022 * degToRad, speed: 2.5, sensitivity: 1.5)

proc updateProjectionMat(c: var Camera) =
  c.projectionMat = case c.kind
  of Orthographic: ortho[GLfloat](
    -c.frustumScale * c.aspectRatio, c.frustumScale * c.aspectRatio,
    -c.frustumScale, c.frustumScale, c.nearClip, c.farClip
  )
  of Perspective: perspective[GLfloat](c.verticalFov, c.aspectRatio, c.nearClip, c.farClip)

proc initPerspectiveCamera(verticalFov, aspectRatio, nearClip, farClip: GLfloat): Camera =
  result = Camera(kind: Perspective, aspectRatio: aspectRatio, verticalFov: verticalFov, nearClip: nearClip, farClip: farClip)
  result.updateProjectionMat()
proc setPerspective(c: var Camera, verticalFov, aspectRatio, nearClip, farClip: GLfloat) =
  c.kind = Perspective
  c.verticalFov = verticalFov
  c.aspectRatio = aspectRatio
  c.nearClip = nearClip
  c.farClip = farClip
  c.updateProjectionMat()

proc initOrthographicCamera(frustumScale, aspectRatio, nearClip, farClip: GLfloat): Camera =
  Camera(kind: Orthographic, aspectRatio: aspectRatio, frustumScale: frustumScale, nearClip: nearClip, farClip: farClip)
proc setOrthographic(c: var Camera, frustumScale, aspectRatio, nearClip, farClip: GLfloat) =
  c.kind = Orthographic
  c.frustumScale = frustumScale
  c.aspectRatio = aspectRatio
  c.nearClip = nearClip
  c.farClip = farClip
  c.updateProjectionMat()

const shadersDir = currentSourcePath().parentDir().parentDir()

var opts = SlangcOptions(
  inFile: shadersDir / "shaders/HelloTriangle.slang", stage: Vertex, entryPoint: "vertexMain", target: Glsl
)
let vertexShaderText = compileShaderOrRaise(opts)

opts = SlangcOptions(
  inFile: shadersDir / "shaders/HelloTriangle.slang", stage: Fragment, entryPoint: "fragmentMain", target: Glsl
)
let fragmentShaderText = compileShaderOrRaise(opts)

var
  # Input
  prevCursorX, prevCursorY: float = 0

  # Renderer state and wrapper objects
  fullscreen = false
  monitor: Monitor
  prevWinProps: tuple[x, y, w, h, refreshRate: int]
  camera: Camera
  shader: ShaderRef
  uniforms: ShaderStorageRef[Uniforms]
  vbo: VertexBufferRef[ColoredVertex]
  vao: VertexArrayRef
  ebo: ElementBufferRef

  # Model data
  vertices = @[
    ColoredVertex(pos: vec3f(0.5, 0.5, 0.0), color: vec3f(1.0, 0.0, 0.0)), # front top right
    ColoredVertex(pos: vec3f(0.5, -0.5, 0.0), color: vec3f(0.0, 1.0, 0.0)), # front bottom right
    ColoredVertex(pos: vec3f(-0.5, -0.5, 0.0), color: vec3f(0.0, 0.0, 1.0)), # front bottom left
    ColoredVertex(pos: vec3f(-0.5,  0.5, 0.0), color: vec3f(0.0, 1.0, 1.0)), # front top left
    ColoredVertex(pos: vec3f(0.5, 0.5, 1.0), color: vec3f(1.0, 0.0, 0.0)), # back top right
    ColoredVertex(pos: vec3f(0.5, -0.5, 1.0), color: vec3f(0.0, 1.0, 0.0)), # back bottom right
    ColoredVertex(pos: vec3f(-0.5, -0.5, 1.0), color: vec3f(0.0, 0.0, 1.0)), # back bottom left
    ColoredVertex(pos: vec3f(-0.5,  0.5, 1.0), color: vec3f(0.0, 1.0, 1.0)) # back top left
  ]
  indices: seq[GLuint] = @[
    0, 1, 3,  1, 2, 3, # front
    0, 4, 1,  1, 4, 5, # right
    3, 2, 7,  2, 6, 7, # left
    1, 5, 2,  2, 5, 6, # bottom
    0, 3, 4,  3, 7, 4, # top
    4, 7, 5,  5, 7, 6 # back
  ]
  modelTransform = Transform(pos: vec3f(0, 0, -2), scale: vec3f(1, 1, 1))

proc getTransformMat(t: Transform): Mat4f =
  var scaleMat, translateMat, rotateMat = mat4f(1.0)
  # Scaling
  scaleMat[0, 0] = t.scale.x
  scaleMat[1, 1] = t.scale.y
  scaleMat[2, 2] = t.scale.z

  # Rotation
  let (cx, cy, cz) = (cos(t.rotation.x), cos(t.rotation.y), cos(t.rotation.z))
  let (sx, sy, sz) = (sin(t.rotation.x), sin(t.rotation.y), sin(t.rotation.z))
  rotateMat[0,0] = cy * cz
  rotateMat[0,1] = -cy * sz
  rotateMat[0,2] = sy
  rotateMat[1,0] = sx * sy * cz + cx * sz
  rotateMat[1,1] = -sx * sy * sz + cx * cz
  rotateMat[1,2] = -sx * cy
  rotateMat[2,0] = -cx * sy * cz + sx * sz
  rotateMat[2,1] = cx * sy * sz + sx * cz
  rotateMat[2,2] = cx * cy

  # Translation
  translateMat[3, 0] = t.pos.x
  translateMat[3, 1] = t.pos.y
  translateMat[3, 2] = t.pos.z
  return translateMat * rotateMat * scaleMat

proc getLocalDirections(c: Camera): tuple[forward, right, up: Vec3f] =
  let
    cosPitch = cos(c.pitch)
    sinPitch = sin(c.pitch)
    cosYaw = cos(c.yaw)
    sinYaw = sin(c.yaw)
    forward = vec3f(cosPitch * cosYaw, sinPitch, cosPitch * -sinYaw).normalize()
    right = cross(forward, vec3f(0, 1, 0)).normalize()
    up = cross(right, forward)
  return (forward, right, up)

proc getCameraViewMat(c: Camera): Mat4f =
  let (forward, right, up) = c.getLocalDirections()
  return lookAt(c.pos, c.pos + forward, up)
proc updateTransform(c: var Camera) = c.viewMat = c.getCameraViewMat()

proc moveLocally(c: var Camera, moveBy: Vec3f) =
  let (forward, right, up) = c.getLocalDirections()
  let moveByWorldSpace = moveBy.x * right + moveBy.y * up - moveBy.z * forward
  c.pos += moveByWorldSpace

proc rotate(c: var Camera; deltaX, deltaY: float) =
  let deltaYaw = deltaX * camOptions.yaw * camOptions.sensitivity
  let deltaPitch = deltaY * camOptions.pitch * camOptions.sensitivity

  c.yaw += deltaYaw
  c.pitch += deltaPitch

  # Prevent vertical flipping
  c.pitch = c.pitch.clamp(-PI / 2, PI / 2)
  # Keep yaw in -180 .. 180 degrees
  if c.yaw > PI: c.yaw -= 2 * PI
  if c.yaw < -PI: c.yaw += 2 * PI

proc updateCameraAspect(win: Window) =
  var (width, height) = glfw.framebufferSize(win)
  var ratio = width / height
  case camera.kind
  of Perspective: camera.setPerspective(camera.verticalFov, ratio, camera.nearClip, camera.farClip)
  of Orthographic: camera.setOrthographic(camera.frustumScale, ratio, camera.nearClip, camera.farClip)

  glViewport(0, 0, width, height)

proc init(win: Window, cfg: OpenglWindowConfig) =
  if cfg.debugContext:
    setupGlDebugLogging()

  win.pos = (150, 100)
  win.aspectRatio = (3, 2)
  win.cursorMode = cmDisabled
  win.rawMouseMotion = true
  echo fmt"raw supported: {rawMouseMotionSupported() != 0}"

  monitor = getPrimaryMonitor()
  camera = initPerspectiveCamera(80, 150 / 100, 0.1, 100)
  camera.pos = vec3f(0, 0, 0)
  camera.updateTransform()
  win.updateCameraAspect()

  # Compile and link shader and check errors
  shader = initShaderProg(vertexShaderText, fragmentShaderText)
  # Get used uniforms/attributes. Bare uniforms don't work in Slang so this uses UBOs.
  uniforms = initShaderStorage[Uniforms](shader, GL_DYNAMIC_DRAW, 0)

  # Set up OpenGL buffers for passing vertex data to shaders
  vbo = initVertexBuffer (vertices, GL_STATIC_DRAW).some
  ebo = initElementBuffer (indices, GL_STATIC_DRAW).some
  vao = initVertexArray()
  vao.use()
  vbo.use()
  vao.attachElementBuffer(ebo)

proc uninit() =
  vbo.cleanup()
  ebo.cleanup()
  vao.cleanup()
  uniforms.cleanup()
  shader.cleanup()

proc update(win: Window, deltaTime: float) =
  # Keyboard input
  var moveBy = vec3f(0)
  if win.isKeyDown(keyComma):
    moveBy.z -= 1
  elif win.isKeyDown(keyO):
    moveBy.z += 1
  if win.isKeyDown(keyE):
    moveBy.x -= 1
  elif win.isKeyDown(keyA):
    moveBy.x += 1
  if win.isKeyDown(keySpace):
    moveBy.y -= 1
  elif win.isKeyDown(keyBackslash):
    moveBy.y += 1

  # Do camera movement
  if moveBy != vec3f(0):
    moveBy = moveBy.normalize() * (camOptions.speed * deltaTime)
    camera.moveLocally(moveBy)

  # Do camera rotation
  let cursorPos = win.cursorPos
  let (cursorDeltaX, cursorDeltaY) = (cursorPos.x - prevCursorX, cursorPos.y - prevCursorY)
  if (cursorDeltaX, cursorDeltaY) != (0.0, 0.0):
    camera.rotate(cursorDeltaX, cursorDeltaY)
  (prevCursorX, prevCursorY) = cursorPos

  camera.updateTransform()

proc keyCb(win: Window, key: Key, scanCode: int32, action: KeyAction, modKeys: set[ModifierKey]) =
  if key == keyEscape and action == kaDown:
    win.shouldClose = true
  elif (key == keyLeftAlt and win.isKeyDown(keyEnter) or
  key == keyEnter and win.isKeyDown(keyLeftAlt)) and action == kaDown:
    if not fullscreen:
      let monitorArea = monitor.workArea()
      let monitorMode = monitor.videoMode()
      prevWinProps = (win.pos.x, win.pos.y, win.size.w, win.size.h, monitorMode.refreshRate)
      echo fmt"Going into fullscreen {(monitorArea.x, monitorArea.y, monitorArea.w, monitorArea.h, monitorMode.refreshRate)}"
      win.monitor = (monitor, monitorArea.x, monitorArea.y, monitorArea.w, monitorArea.h, monitorMode.refreshRate)
    else:
      echo fmt"Going out of fullscreen {(prevWinProps.x, prevWinProps.y, prevWinProps.w, prevWinProps.h, prevWinProps.refreshRate)}"
      win.monitor = (newMonitor(nil), prevWinProps.x, prevWinProps.y, prevWinProps.w, prevWinProps.h, prevWinProps.refreshRate)
    fullscreen = not fullscreen

#[ 
On Wayland, win.monitor seems to return null...

proc positionCb(win: Window, pos: tuple[x, y: int32]) =
  monitor = win.monitor
]#

proc sizeCb(win: Window; size: tuple[w, h: int32]) =
  win.updateCameraAspect()

proc draw(win: Window) =
  glClearColor(0.2, 0.3, 0.3, 1.0)
  glClear(GL_COLOR_BUFFER_BIT)

  shader.use()
  uniforms.data.mvp = camera.projectionMat * camera.viewMat * modelTransform.getTransformMat()
  uniforms.upload()
  uniforms.use(shader)
  vao.use()
  glDrawElements(GL_TRIANGLES, indices.len, GL_UNSIGNED_INT, cast[pointer](0))

proc main() =
  glfw.initialize()
  var cfg = DefaultOpenglWindowConfig
  cfg.size = (w: 640, h: 480)
  cfg.title = "Simple example"
  cfg.resizable = true
  cfg.version = glv46
  cfg.forwardCompat = true
  cfg.profile = opCoreProfile
  # Setting to true enables debug logging
  cfg.debugContext = true

  var win = newWindow(cfg)
  win.keyCb = keyCb
  win.windowSizeCb = sizeCb

  if not gladLoadGL(getProcAddress):
    quit "Error initialising OpenGL"

  glfw.swapInterval(1)
  init(win, cfg)

  var prevFrameStart = getTime()
  while not win.shouldClose:
    let currFrameStart = getTime()
    let deltaTime = currFrameStart - prevFrameStart
    prevFrameStart = currFrameStart
    update(win, deltaTime)
    draw(win)

    glfw.swapBuffers(win)
    glfw.pollEvents()

  uninit()
  glfw.terminate()

main()
