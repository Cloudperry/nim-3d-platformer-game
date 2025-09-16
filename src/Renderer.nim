import std/[os, strformat, options, math]

import pkg/[glm, glfw]
from pkg/glfw/wrapper import `rawMouseMotionSupported`
import ./glad/gl
import GlUtils, Slangc, Scene

type
  ColoredVertex = object
    pos, color: Vec3f
  # Packed pragma might be necessary or more correct for structs passed to GPU?
  Uniforms = object
    mvp: Mat4f

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
  cameraOpts: FpCameraOptions
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
