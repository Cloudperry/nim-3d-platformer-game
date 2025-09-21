import std/[os, strformat, options, math, monotimes, sequtils]
import std/times except `getTime`
import pkg/[glm, glfw, cligen]
from pkg/glfw/wrapper import `rawMouseMotionSupported`
import ./glad/gl
import GlUtils, Slangc, Scene, CircularBuffer, Shapes

makeGlObjects(std140Alignment):
  type
    # GPU side representation of the scene objects from Scene.nim
    # GpuSceneStorage[T] = object
    #  discard

    GpuSceneUniforms = object
      cameraPos: Vec3f
      # Just one model to world transform for now, separate transforms for each model will be needed later
      modelToWorldMat, worldToViewMat, viewToClipMat: Mat4f 
      mainLightDirection: Vec3f
      mainLightColor: Vec3f
      ambientLightColor: Vec3f

const
  cubeColor = vec3f(1.0)
  shadersDir = currentSourcePath().parentDir().parentDir()
  logPeriod = initDuration(milliseconds = 250)

let
  cube = makeCube(vec3f(1))
  pyramid = makePyramid(vec3f(1))
  sphere = makeSphere(0.5, 16, 16, vec3f(1))

var
  # Shaders
  vertexShaderText, fragmentShaderText: string

  # Input
  prevCursorX, prevCursorY: float = 0

  # Renderer state and wrapper objects
  fullscreen = false
  monitor: Monitor
  prevWinProps: tuple[x, y, w, h, refreshRate: int]
  camera: Camera
  cameraOpts: FpCameraOptions
  shader: ShaderRef
  uniforms: ShaderDataBufferRef[GpuSceneUniforms]
  vertexBuffers: seq[VertexBufferRef[ColoredVertex]]
  elementBuffers: seq[ElementBufferRef]
  vertexArrays: seq[VertexArrayRef]

  # Performance logging
  updateTimes, drawTimes, frameTimes: CircularBuffer[1000, Duration]
  timeSinceLastLog = initDuration()
  lastLogI = 0
  lastStatusLineContent = ""

  cubeModel = initModel(
    cube.vertices, cube.indices, transform = Transform(pos: vec3f(0, 0, -2), scale: vec3f(1, 1, 1))
  )
  pyramidModel = initModel(
    pyramid.vertices, pyramid.indices, transform = Transform(pos: vec3f(-2, 0, -2), scale: vec3f(1, 1, 1))
  )
  sphereModel = initModel(
    sphere.vertices, sphere.indices, transform = Transform(pos: vec3f(2, 0, -2), scale: vec3f(1, 1, 1))
  )
  scene = initScene(
    camera,
    @[cubeModel, pyramidModel, sphereModel],
    DirectionalLight(direction: vec3f(8, 5, 3).normalize(), color: vec3f(1, 0.6, 0.3)).some,
    vec3f(0.1).some
  )

# Extend this into a small logging library? It could just write the "terminal status line" in the logs normally when isatty(f) is false.
proc clearLine(f: var File) = f.write "\x1b[2K"

proc writeTerminalStatusLine(f: var File, msg: Option[string] = string.none) = 
  f.write '\r'
  f.clearLine()

  let msg = if msg.isSome:
    msg.get
  else:
    lastStatusLineContent
  f.write msg

  f.flushFile()

proc logMessage(f: var File, msg: string) =
  f.clearLine()
  f.write '\r'
  f.writeLine msg
  f.writeTerminalStatusLine()

proc updateCameraAspect(win: Window) =
  var (width, height) = glfw.framebufferSize(win)
  var ratio = width / height
  case camera.kind
  of Perspective: camera.setPerspective(camera.verticalFov, ratio, camera.nearClip, camera.farClip)
  of Orthographic: camera.setOrthographic(camera.frustumScale, ratio, camera.nearClip, camera.farClip)

  glViewport(0, 0, width, height)

proc makeGlBuffers[T](s: Scene[T]) =
  vertexBuffers.setLen s.models.len
  elementBuffers.setLen s.models.len
  vertexArrays.setLen s.models.len

  for i, model in s.models:
    vertexBuffers[i] = initVertexBuffer (model.vertices, GL_STATIC_DRAW).some
    elementBuffers[i] = initElementBuffer (model.indices, GL_STATIC_DRAW).some
    vertexArrays[i] = initVertexArray()
    vertexArrays[i].use()
    vertexBuffers[i].use()
    vertexArrays[i].attachElementBuffer(elementBuffers[i])

proc setSceneUniforms[T](s: Scene[T]) =
  uniforms.setField(mainLightDirection, s.dirLight.direction)
  uniforms.setField(mainLightColor, s.dirLight.color)
  uniforms.setField(ambientLightColor, s.ambientLightColor)

proc init(win: Window) =
  camera = initPerspectiveCamera(80, 150 / 100, 0.1, 100)
  camera.pos = vec3f(0, 0, 0)
  camera.updateTransform()
  # Set camera options to defaults. Mouse sensitivity is fast on a gaming mouse, but might be too slow for a normal mouse.
  cameraOpts = FpCameraOptions() 
  win.updateCameraAspect()

  # Compile and link shader and check errors
  shader = initShaderProg(vertexShaderText, fragmentShaderText)
  # Get used uniforms/attributes. Bare uniforms don't work in Slang so this uses UBOs.
  uniforms = initShaderDataBuffer[GpuSceneUniforms](shader, 0, GL_UNIFORM_BUFFER, GL_DYNAMIC_DRAW)

  # Set up OpenGL buffers for passing vertex data to shaders
  scene.makeGlBuffers()
  scene.setSceneUniforms()

  # Enable backface culling
  glEnable(GL_CULL_FACE)
  glCullFace(GL_BACK)
  glFrontFace(GL_CCW)

proc uninit() =
  for i in 0 .. vertexArrays.high:
    vertexBuffers[i].cleanup()
    elementBuffers[i].cleanup()
    vertexArrays[i].cleanup()
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
      stdout.logMessage fmt"Going into fullscreen {(monitorArea.x, monitorArea.y, monitorArea.w, monitorArea.h, monitorMode.refreshRate)}"
      win.monitor = (monitor, monitorArea.x, monitorArea.y, monitorArea.w, monitorArea.h, monitorMode.refreshRate)
    else:
      stdout.logMessage fmt"Going out of fullscreen {(prevWinProps.x, prevWinProps.y, prevWinProps.w, prevWinProps.h, prevWinProps.refreshRate)}"
      win.monitor = (newMonitor(nil), prevWinProps.x, prevWinProps.y, prevWinProps.w, prevWinProps.h, prevWinProps.refreshRate)
    fullscreen = not fullscreen

#[ 
Would be nice to keep track of the monitor the window is on, but on Wayland, win.monitor seems to return null...

proc positionCb(win: Window, pos: tuple[x, y: int32]) =
  monitor = win.monitor
]#

proc sizeCb(win: Window; size: tuple[w, h: int32]) =
  win.updateCameraAspect()

proc setUniforms(m: Model) =
  uniforms.setField(modelToWorldMat, m.transform.getTransformMat())

proc setUniforms(c: Camera) =
  uniforms.setField(worldToViewMat, c.viewMat)
  uniforms.setField(viewToClipMat, c.projectionMat)

proc draw(win: Window) =
  glClearColor(0.2, 0.3, 0.3, 1.0)
  glClear(GL_COLOR_BUFFER_BIT)

  shader.use()
  uniforms.use(shader)
  camera.setUniforms()

  for i in 0 .. vertexArrays.high:
    vertexArrays[i].use()
    scene.models[i].setUniforms()
    glDrawElements(GL_TRIANGLES, scene.models[i].indices.len, GL_UNSIGNED_INT, cast[pointer](0))

proc logPerf(update, draw, frame: Duration) =
  updateTimes.push update
  drawTimes.push draw
  frameTimes.push frame
  timeSinceLastLog += frame

  if timeSinceLastLog >= logPeriod:
    var updateSum, drawSum, frameTimeSum = initDuration()
    var count = 0
    for time in updateTimes.range(lastLogI, updateTimes.i): updateSum += time
    for time in drawTimes.range(lastLogI, drawTimes.i): drawSum += time
    for time in frameTimes.range(lastLogI, frameTimes.i): 
      frameTimeSum += time
      count += 1

    timeSinceLastLog = initDuration()
    lastLogI = frameTimes.i

    let (updateAvg, drawAvg) = (inMicroseconds(updateSum div count), inMicroseconds(drawSum div count))
    let fpsAvg = initDuration(seconds = 1).inNanoseconds() / inNanoseconds(frameTimeSum div count)
    stdout.writeTerminalStatusLine fmt"Update: {updateAvg} μs, Draw: {drawAvg} μs, FPS: {fpsAvg:.1f}".some

proc compileShaders(slangPath = "") =
  var opts = SlangcOptions(
    inFile: shadersDir / "shaders/RasterizedRenderer.slang", stage: Vertex, entryPoint: "vertexMain", target: Glsl
  )
  if slangPath.len > 0: opts.slangPath = slangPath
  vertexShaderText = compileShaderOrRaise(opts)

  opts.stage = Fragment
  opts.entryPoint = "fragmentMain"
  fragmentShaderText = compileShaderOrRaise(opts)

proc main(slangPath: string = "") =
  compileShaders(slangPath)

  # GLFW window and OpenGL context init
  glfw.initialize()
  var cfg = DefaultOpenglWindowConfig
  cfg.size = (w: 640, h: 480)
  cfg.title = "Simple example"
  cfg.resizable = true
  cfg.version = glv46
  cfg.forwardCompat = true
  cfg.profile = opCoreProfile
  cfg.debugContext = not (defined(release) or defined(danger))

  # GLFW init that has to be done after window creation
  var win = newWindow(cfg)
  if not gladLoadGL(getProcAddress):
    quit "Error initialising OpenGL"

  win.keyCb = keyCb
  win.windowSizeCb = sizeCb
  win.pos = (150, 100)
  win.aspectRatio = (3, 2)
  win.cursorMode = cmDisabled
  monitor = getPrimaryMonitor()
  if rawMouseMotionSupported() != 0:
    win.rawMouseMotion = true
  else:
    stdout.logMessage "Raw mouse motion not supported. Camera rotation speed will be dependent on desktop mouse settings."

  if cfg.debugContext: # Enable debug logging when using an OpenGL debug context
    setupGlDebugLogging()

  glfw.swapInterval(1)
  init(win)

  var prevFrameStart = getMonoTime()
  while not win.shouldClose:
    let currFrameStart = getMonoTime()
    let frameDuration = currFrameStart - prevFrameStart
    let deltaTime = frameDuration.inNanoseconds() / initDuration(seconds = 1).inNanoseconds()
    prevFrameStart = currFrameStart
    
    update(win, deltaTime)
    let updateEnd = getMonoTime()
    draw(win)
    let drawEnd = getMonoTime()

    glfw.swapBuffers(win)
    let currFrameEnd = getMonoTime()
    logPerf(updateEnd - currFrameStart, drawEnd - updateEnd, currFrameEnd - currFrameStart)

    glfw.pollEvents()

  uninit()
  glfw.terminate()

when isMainModule:
  dispatch main
