import std/[os, strformat, options, math]

import pkg/[glm, glfw]
from pkg/glfw/wrapper import `rawMouseMotionSupported`
import ./glad/gl
import GlUtils, Slangc, Scene

type
  # GPU side representation of the scene objects from Scene.nim
  GpuSceneStorage[T] = object
    discard

  GpuSceneUniforms {.packed.} = object
    # TODO: Make a macro that does OpenGL std140 padding automatically. This obj has manual padding that is very ugly.
    cameraPos: Vec3f
    # Just one model to world transform for now, separate transforms for each model will be needed later
    modelToWorldMat {.align(16).}, worldToViewMat, viewToClipMat: Mat4f 
    mainLightDirection: Vec3f
    mainLightColor {.align(16).}: Vec3f
    ambientLightColor {.align(16).}: Vec3f

const shadersDir = currentSourcePath().parentDir().parentDir()

var opts = SlangcOptions(
  inFile: shadersDir / "shaders/RasterizedRenderer.slang", stage: Vertex, entryPoint: "vertexMain", target: Glsl
)
let vertexShaderText = compileShaderOrRaise(opts)

opts = SlangcOptions(
  inFile: shadersDir / "shaders/RasterizedRenderer.slang", stage: Fragment, entryPoint: "fragmentMain", target: Glsl
)
let fragmentShaderText = compileShaderOrRaise(opts)

let cubeColor = vec3f(0.9)
var
  # Input
  prevCursorX, prevCursorY: float = 0

  # Renderer state and wrapper objects
  fullscreen = false
  monitor: Monitor
  prevWinProps: tuple[x, y, w, h, refreshRate: int]
  camera: Camera
  cameraOpts: FpCameraOptions
  shader: ShaderRef
  uniforms: ShaderStorageRef[GpuSceneUniforms]
  vbo: VertexBufferRef[ColoredVertex]
  vao: VertexArrayRef
  ebo: ElementBufferRef

  # Model data (cube with per face normals)
  vertices = @[
    # Front face (z = 0.5, normal = +Z)
    ColoredVertex(pos: vec3f(-0.5, -0.5,  0.5), color: cubeColor, normal: vec3f(0, 0, 1)),
    ColoredVertex(pos: vec3f( 0.5, -0.5,  0.5), color: cubeColor, normal: vec3f(0, 0, 1)),
    ColoredVertex(pos: vec3f( 0.5,  0.5,  0.5), color: cubeColor, normal: vec3f(0, 0, 1)),
    ColoredVertex(pos: vec3f(-0.5,  0.5,  0.5), color: cubeColor, normal: vec3f(0, 0, 1)),

    # Back face (z = -0.5, normal = -Z)
    ColoredVertex(pos: vec3f(-0.5, -0.5, -0.5), color: cubeColor, normal: vec3f(0, 0, -1)),
    ColoredVertex(pos: vec3f( 0.5, -0.5, -0.5), color: cubeColor, normal: vec3f(0, 0, -1)),
    ColoredVertex(pos: vec3f( 0.5,  0.5, -0.5), color: cubeColor, normal: vec3f(0, 0, -1)),
    ColoredVertex(pos: vec3f(-0.5,  0.5, -0.5), color: cubeColor, normal: vec3f(0, 0, -1)),

    # Left face (x = -0.5, normal = -X)
    ColoredVertex(pos: vec3f(-0.5, -0.5, -0.5), color: cubeColor, normal: vec3f(-1, 0, 0)),
    ColoredVertex(pos: vec3f(-0.5, -0.5,  0.5), color: cubeColor, normal: vec3f(-1, 0, 0)),
    ColoredVertex(pos: vec3f(-0.5,  0.5,  0.5), color: cubeColor, normal: vec3f(-1, 0, 0)),
    ColoredVertex(pos: vec3f(-0.5,  0.5, -0.5), color: cubeColor, normal: vec3f(-1, 0, 0)),

    # Right face (x = 0.5, normal = +X)
    ColoredVertex(pos: vec3f( 0.5, -0.5, -0.5), color: cubeColor, normal: vec3f(1, 0, 0)),
    ColoredVertex(pos: vec3f( 0.5, -0.5,  0.5), color: cubeColor, normal: vec3f(1, 0, 0)),
    ColoredVertex(pos: vec3f( 0.5,  0.5,  0.5), color: cubeColor, normal: vec3f(1, 0, 0)),
    ColoredVertex(pos: vec3f( 0.5,  0.5, -0.5), color: cubeColor, normal: vec3f(1, 0, 0)),

    # Top face (y = 0.5, normal = +Y)
    ColoredVertex(pos: vec3f(-0.5,  0.5, -0.5), color: cubeColor, normal: vec3f(0, 1, 0)),
    ColoredVertex(pos: vec3f( 0.5,  0.5, -0.5), color: cubeColor, normal: vec3f(0, 1, 0)),
    ColoredVertex(pos: vec3f( 0.5,  0.5,  0.5), color: cubeColor, normal: vec3f(0, 1, 0)),
    ColoredVertex(pos: vec3f(-0.5,  0.5,  0.5), color: cubeColor, normal: vec3f(0, 1, 0)),

    # Bottom face (y = -0.5, normal = -Y)
    ColoredVertex(pos: vec3f(-0.5, -0.5, -0.5), color: cubeColor, normal: vec3f(0, -1, 0)),
    ColoredVertex(pos: vec3f( 0.5, -0.5, -0.5), color: cubeColor, normal: vec3f(0, -1, 0)),
    ColoredVertex(pos: vec3f( 0.5, -0.5,  0.5), color: cubeColor, normal: vec3f(0, -1, 0)),
    ColoredVertex(pos: vec3f(-0.5, -0.5,  0.5), color: cubeColor, normal: vec3f(0, -1, 0))
  ]

  indices: seq[GLuint] = @[
    # Front
    0, 1, 2,  0, 2, 3,
    # Back
    4, 6, 5,  4, 7, 6,
    # Left
    8, 9, 10,  8, 10, 11,
    # Right
    12, 14, 13,  12, 15, 14,
    # Top
    16, 18, 17,  16, 19, 18,
    # Bottom
    20, 21, 22,  20, 22, 23
  ]
  modelTransform = Transform(pos: vec3f(0, 0, -2), scale: vec3f(1, 1, 1))

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
  if rawMouseMotionSupported() != 0:
    win.rawMouseMotion = true
  else:
    echo "Raw mouse motion not supported. Camera rotation speed will be dependent on desktop mouse settings."

  monitor = getPrimaryMonitor()
  camera = initPerspectiveCamera(80, 150 / 100, 0.1, 100)
  camera.pos = vec3f(0, 0, 0)
  camera.updateTransform()
  # Set camera options to defaults. Mouse sensitivity is fast on a gaming mouse, but might be too slow for a normal mouse.
  cameraOpts = FpCameraOptions() 
  win.updateCameraAspect()

  # Compile and link shader and check errors
  shader = initShaderProg(vertexShaderText, fragmentShaderText)
  # Get used uniforms/attributes. Bare uniforms don't work in Slang so this uses UBOs.
  uniforms = initShaderStorage[GpuSceneUniforms](shader, GL_DYNAMIC_DRAW, 0)

  # Set up OpenGL buffers for passing vertex data to shaders
  vbo = initVertexBuffer (vertices, GL_STATIC_DRAW).some
  ebo = initElementBuffer (indices, GL_STATIC_DRAW).some
  vao = initVertexArray()
  vao.use()
  vbo.use()
  vao.attachElementBuffer(ebo)

  # Enable backface culling
  glEnable(GL_CULL_FACE)
  glCullFace(GL_BACK)
  glFrontFace(GL_CCW)

proc uninit() =
  vbo.cleanup()
  ebo.cleanup()
  vao.cleanup()
  uniforms.cleanup()
  shader.cleanup()

proc update(win: Window, deltaTime: float) =
  # Keyboard input
  var moveDirection = vec3f(0)
  if win.isKeyDown(keyComma):
    moveDirection.z -= 1
  elif win.isKeyDown(keyO):
    moveDirection.z += 1
  if win.isKeyDown(keyE):
    moveDirection.x -= 1
  elif win.isKeyDown(keyA):
    moveDirection.x += 1
  if win.isKeyDown(keySpace):
    moveDirection.y -= 1
  elif win.isKeyDown(keyBackslash):
    moveDirection.y += 1

  let cursorPos = win.cursorPos
  let (cursorDeltaX, cursorDeltaY) = (cursorPos.x - prevCursorX, cursorPos.y - prevCursorY)
  (prevCursorX, prevCursorY) = cursorPos

  camera.doFirstPersonCameraMovement(cameraOpts, moveDirection, cursorDeltaX, cursorDeltaY, deltaTime)

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
Would be nice to keep track of the monitor the window is on, but on Wayland, win.monitor seems to return null...

proc positionCb(win: Window, pos: tuple[x, y: int32]) =
  monitor = win.monitor
]#

proc sizeCb(win: Window; size: tuple[w, h: int32]) =
  win.updateCameraAspect()

proc draw(win: Window) =
  glClearColor(0.2, 0.3, 0.3, 1.0)
  glClear(GL_COLOR_BUFFER_BIT)

  shader.use()
  uniforms.data.modelToWorldMat = modelTransform.getTransformMat()
  uniforms.data.worldToViewMat = camera.viewMat
  uniforms.data.viewToClipMat = camera.projectionMat
  uniforms.data.mainLightColor = vec3f(1, 0.6, 0.3)
  uniforms.data.mainLightDirection = vec3f(8, 5, 3).normalize()
  uniforms.data.ambientLightColor = vec3f(0.1)
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
