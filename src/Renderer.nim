import std/[os, strformat, options]

import pkg/[glm, glfw]
import ./glad/gl
import GlUtils, Slangc

type
  ColoredVertex = object
    pos, color: Vec3f
  # Packed pragma might be necessary or more correct for structs passed to GPU?
  Uniforms = object
    mvp: Mat4f
  Transform = object
    pos: Vec3[float]
    scale: Vec3[float]
    rotation: Vec3[float]

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
  # Renderer state and wrapper objects
  fullscreen = false
  monitor: Monitor
  prevWinProps: tuple[x, y, w, h, refreshRate: int]
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
    # front
    0, 1, 3,  1, 2, 3,
    # right
    0, 4, 1,  1, 4, 5,
    # left
    3, 2, 7,  2, 6, 7,
    # bottom
    1, 5, 2,  2, 5, 6,
    # top
    0, 3, 4,  3, 7, 4,
    # back
    4, 7, 5,  5, 7, 6
  ]
  modelTransform = Transform(pos: vec3d(0, 0, 0), scale: vec3d(1, 1, 1))

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

proc init(win: Window, cfg: OpenglWindowConfig) =
  if cfg.debugContext:
    setupGlDebugLogging()

  # Starting window parameters
  win.pos = (150, 100)
  win.aspectRatio = (3, 2)
  monitor = getPrimaryMonitor()

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
  if win.isKeyDown(keyComma):
    modelTransform.pos.z -= deltaTime * 1
  elif win.isKeyDown(keyO):
    modelTransform.pos.z += deltaTime * 1
  elif win.isKeyDown(keyE):
    modelTransform.pos.x += deltaTime * 1
  elif win.isKeyDown(keyA):
    modelTransform.pos.x -= deltaTime * 1
  elif win.isKeyDown(keySpace):
    modelTransform.pos.y += deltaTime * 1
  elif win.isKeyDown(keyBackslash):
    modelTransform.pos.y -= deltaTime * 1

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

proc draw(win: Window) =
  var (width, height) = glfw.framebufferSize(win)
  var ratio = width / height

  glViewport(0, 0, width, height)
  let viewMat = ortho[GLfloat](-ratio, ratio, -1.0, 1.0, 1.0, -1.0)
  glClearColor(0.2, 0.3, 0.3, 1.0)
  glClear(GL_COLOR_BUFFER_BIT)

  shader.use()
  uniforms.data.mvp = viewMat * modelTransform.getTransformMat()
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
