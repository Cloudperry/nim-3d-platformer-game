import std/[os, strformat, options, math, monotimes, importutils, tables, times]
import std/times except `getTime`
import pkg/[glm, glfw, confutils]
from pkg/glfw/wrapper import `rawMouseMotionSupported`
import
  ./[
    GlUtils, Slangc, Logger, SceneLogic, CameraController, Input, TestScenes, GameLogic
  ]
import ./glad/gl

makeGlObjects(RaiseError, std140Alignment):
  type GpuSceneUniforms = object
    cameraPos: Vec3f
    # Just one model to world transform for now, separate transforms for each model will be needed later
    modelToWorldMat, worldToViewMat, viewToClipMat: Mat4f
    mainLightDirection: Vec3f
    mainLightColor: Vec3f
    ambientLightColor: Vec3f

type
  AxisInputs = enum
    Mouse

  State = object # Window/input
    fullscreen: bool
    monitor: Monitor
    prevWinProps: tuple[x, y, w, h, refreshRate: int]
    prevCursorX, prevCursorY: float
    # Renderer state and wrapper objects
    vertexShaderText, fragmentShaderText: string
    shader: ShaderRef
    uniforms: ShaderDataBufferRef[GpuSceneUniforms]
    pointLights: ShaderDataBufferRef[seq[PointLight]]
    vertexBuffers: seq[VertexBufferRef[ColoredVertex]]
    elementBuffers: seq[ElementBufferRef]
    vertexArrays: seq[VertexArrayRef]

const
  shadersDir = "shaders"
  buttonActions: InputsToActions[ActionNames, Key] = {
    keyComma: MoveFwd,
    keyW: MoveFwd,
    keyO: MoveBack,
    keyS: MoveBack,
    keyE: MoveRight,
    keyD: MoveRight,
    keyA: MoveLeft,
    keySpace: Jump,
    keyBackslash: FlyDown,
    keyLeftShift: FlyDown,
  }.toTable
  axisActions: InputsToActions[ActionNames, AxisInputs] = {Mouse: TurnCamera}.toTable

var
  state = State()
  game: GameStateRef

proc updateCameraAspect(win: Window, width, height: int) =
  var ratio = width / height
  if game != nil and game.playerI != 0:
    game.cam.aspectRatio = ratio
    game.cam.updateProjectionMat()

    glViewport(0, 0, width, height)

proc makeGlBuffers[T](s: Scene[T]) =
  state.vertexBuffers.setLen s.models.len
  state.elementBuffers.setLen s.models.len
  state.vertexArrays.setLen s.models.len

  for i, model in s.models:
    state.vertexBuffers[i] = initVertexBuffer (model.vertices, GL_STATIC_DRAW).some
    state.elementBuffers[i] = initElementBuffer (model.indices, GL_STATIC_DRAW).some
    state.vertexArrays[i] = initVertexArray()
    state.vertexArrays[i].use()
    state.vertexBuffers[i].use()
    state.vertexArrays[i].attachElementBuffer(state.elementBuffers[i])

proc setSceneUniforms[T](s: Scene[T]) =
  state.uniforms.mainLightDirection = s.dirLight.direction
  state.uniforms.mainLightColor = s.dirLight.color
  state.uniforms.ambientLightColor = s.ambientLightColor

proc init(win: Window) =
  let monitorSize = (state.monitor.workArea.w, state.monitor.workArea.h)
  state.fullscreen = win.size == monitorSize

  stdout.initGlobalLogger()

  let (width, height) = glfw.framebufferSize(win)
  win.updateCameraAspect(width, height)

  # Compile and link shader and check errors
  state.shader = initShaderProg(state.vertexShaderText, state.fragmentShaderText)
  # Get used uniforms/attributes. Bare uniforms don't work in Slang so this uses UBOs.
  state.uniforms = initShaderDataBuffer[GpuSceneUniforms](
    state.shader, 0, GL_UNIFORM_BUFFER, GL_DYNAMIC_DRAW
  )

  # Set up OpenGL buffers for passing data to shaders
  game.scene.setSceneUniforms()
  game.scene.makeGlBuffers()
  state.pointLights = initShaderDataBuffer[seq[PointLight]](
    state.shader, 1, GL_SHADER_STORAGE_BUFFER, GL_DYNAMIC_DRAW
  )
  state.pointLights.loadTestSceneLights()
  state.pointLights.upload()

  # Enable backface culling
  glEnable(GL_CULL_FACE)
  glCullFace(GL_BACK)
  glFrontFace(GL_CCW)

  # Enable depth buffer to for correct occlusion when rendering multiple objects 
  glEnable(GL_DEPTH_TEST)
  glDepthFunc(GL_LESS)

proc getAxis(win: Window, a: AxisInputs): Vec2f =
  case a
  of Mouse:
    result =
      vec2f(win.cursorPos.x - state.prevCursorX, win.cursorPos.y - state.prevCursorY)
    (state.prevCursorX, state.prevCursorY) = win.cursorPos

proc update(win: Window) =
  game.preUpdate()

  if game.conf.replayName.len == 0:
    # Mouse input
    game.replaySystem.addRecordingInputReader(
      axisActions,
      proc(a: AxisInputs): Vec2f =
        win.getAxis(a),
      game.frameCount,
      game.frame.deltaTime,
      game.conf.recordInputs,
    )

    # Keyboard input
    game.replaySystem.addRecordingInputReader(
      buttonActions,
      proc(k: Key): bool =
        win.isKeyDown(k),
      game.frameCount,
      game.frame.deltaTime,
      game.conf.recordInputs,
    )

  game.update()

proc deinit() =
  for i in 0 .. state.vertexArrays.high:
    state.vertexBuffers[i].deinit()
    state.elementBuffers[i].deinit()
    state.vertexArrays[i].deinit()
  state.uniforms.deinit()
  state.shader.deinit()

  game.deinit()

proc setUniforms(m: Model) =
  state.uniforms.modelToWorldMat = m.transform.getTransformMat()

proc setUniforms(c: CameraData)
proc draw() =
  glClearColor(0.2, 0.3, 0.3, 1.0)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

  state.shader.use()
  state.uniforms.use(state.shader)
  game.cam.setUniforms()

  for i in 0 .. state.vertexArrays.high:
    state.vertexArrays[i].use()
    game.scene.models[i].setUniforms()
    glDrawElements(
      GL_TRIANGLES, game.scene.models[i].indices.len, GL_UNSIGNED_INT, cast[pointer](0)
    )

proc sizeCb(win: Window, size: tuple[w, h: int32]) =
  win.updateCameraAspect(size.w, size.h)

proc setUniforms(c: CameraData) =
  state.uniforms.worldToViewMat = c.viewMat
  state.uniforms.viewToClipMat = c.projectionMat

proc keyCb(
    win: Window, key: Key, scanCode: int32, action: KeyAction, modKeys: set[ModifierKey]
) =
  if key == keyEscape and action == kaDown:
    win.shouldClose = true
  if key == keyP and action == kaDown:
    let pos = $game.scene.entities[game.playerI].t.pos
    let cam = game.scene.entities[game.playerI].camera
    let rotation = fmt"{cam.yaw}, {cam.pitch}"
    globalLogger.log fmt"Player position: {pos}, player rotation: ({rotation})"
  elif (
    key == keyLeftAlt and win.isKeyDown(keyEnter) or
    key == keyEnter and win.isKeyDown(keyLeftAlt)
  ) and action == kaDown:
    if not state.fullscreen:
      let monitorArea = state.monitor.workArea()
      let monitorMode = state.monitor.videoMode()
      state.prevWinProps =
        (win.pos.x, win.pos.y, win.size.w, win.size.h, monitorMode.refreshRate)
      globalLogger.log fmt"Going into fullscreen {(monitorArea.x, monitorArea.y, monitorArea.w, monitorArea.h, monitorMode.refreshRate)}"
      win.monitor = (
        state.monitor, monitorArea.x, monitorArea.y, monitorArea.w, monitorArea.h,
        monitorMode.refreshRate,
      )
    else:
      let winProps = (
        state.prevWinProps.x, state.prevWinProps.y, state.prevWinProps.w,
        state.prevWinProps.h, state.prevWinProps.refreshRate,
      )
      globalLogger.log fmt"Going out of fullscreen {winProps}"
      win.monitor = (
        newMonitor(nil),
        state.prevWinProps.x,
        state.prevWinProps.y,
        state.prevWinProps.w,
        state.prevWinProps.h,
        state.prevWinProps.refreshRate,
      )
    state.fullscreen = not state.fullscreen

  # TODO: Camera is not getting updated using the window size callback on fullscreen. This is a hack to update it.
  # Find out why size callbacks don't fire on fullscreen.
  let (width, height) = glfw.framebufferSize(win)
  win.updateCameraAspect(width, height)

proc positionCb(win: Window, pos: tuple[x, y: int32]) =
  let newMonitor = win.monitor
  privateAccess(newMonitor.type)
  if newMonitor.handle != nil:
    # Linux Wayland sometimes gave nil monitors for win.monitor, check that its not nil
    state.monitor = newMonitor

const isDebugBuild = not (defined(release) or defined(danger))

proc loadShader(o: SlangcOptions): string =
  let filename = o.getOutputFilename()
  return readFile(filename)

proc loadShaders(slangBinPath = "") =
  let inFile = shadersDir / "RasterizedRenderer.slang"
  let vertOpts = initSlangcOptions(inFile, Vertex)
  let fragOpts = initSlangcOptions(inFile, Fragment)

  when isDebugBuild:
    state.vertexShaderText = compileShaderOrRaise(vertOpts, slangBinPath)
    state.fragmentShaderText = compileShaderOrRaise(fragOpts, slangBinPath)
  else:
    state.vertexShaderText = loadShader(vertOpts)
    state.fragmentShaderText = loadShader(fragOpts)

proc initGlfwAndGlad(): tuple[win: Window, cfg: OpenglWindowConfig] =
  # GLFW window and OpenGL context init
  glfw.initialize()
  var cfg = DefaultOpenglWindowConfig
  cfg.size = (w: 1280, h: 720)
  cfg.title = appDesc
  cfg.resizable = true
  cfg.version = glv46
  cfg.forwardCompat = true
  cfg.profile = opCoreProfile
  cfg.debugContext = isDebugBuild
  cfg.bits.depth = 24.some

  # GLFW init that has to be done after window creation
  var win = newWindow(cfg)
  if not gladLoadGL(getProcAddress):
    quit "Error initialising OpenGL"
  if cfg.debugContext: # Enable debug logging when using an OpenGL debug context
    #[
    This proc probably needs to be global for it to not cause a segfault as the logger proc
    let glDebugLoggerProc: LoggerProc = proc (msg: string) =
      log msg
    setGlDebugLoggerProc glDebugLoggerProc
    ]#
    setupGlDebugLogging()

  win.keyCb = keyCb
  win.windowSizeCb = sizeCb
  win.windowPositionCb = positionCb
  win.aspectRatio = (3, 2)
  win.cursorMode = cmDisabled
  state.monitor = getPrimaryMonitor()

  if rawMouseMotionSupported() != 0:
    win.rawMouseMotion = true
  else:
    globalLogger.log "Raw mouse motion not supported. Camera rotation speed will be dependent on desktop mouse settings."

  # TODO: Allow running faster than VSync when playing higher than monitor refresh rate replays
  glfw.swapInterval(game.conf.swapInterval)
  return (win, cfg)

const maxDeltaTime = 1.0 / 30.0 # Delta time for 30 FPS

proc main() =
  game = initGameState()
  loadShaders(game.conf.slangBinPath)
  if game.conf.compileShadersAndQuit:
    quit()

  var (win, cfg) = initGlfwAndGlad()
  win.init()

  var prevFrameStart = getMonoTime()
  while not win.shouldClose:
    let currFrameStart = getMonoTime()
    let frameDuration = currFrameStart - prevFrameStart
    game.frame.deltaTime =
      frameDuration.inNanoseconds() / initDuration(seconds = 1).inNanoseconds()
    # Clamp deltaTime to being less than maxDeltaTime to prevent the simulation from taking too large steps
    game.frame.deltaTime = min(maxDeltaTime, game.frame.deltaTime)
    game.frame.monoTime = currFrameStart
    prevFrameStart = currFrameStart

    win.update()
    let updateEnd = getMonoTime()
    draw()
    glfw.swapBuffers(win)

    let currFrameEnd = getMonoTime()
    logPerf(
      updateEnd - currFrameStart,
      currFrameEnd - updateEnd,
      currFrameEnd - currFrameStart,
    )

    glfw.pollEvents()
  deinit()
  glfw.terminate()

main()
