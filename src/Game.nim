import
  std/[
    os, strformat, options, math, monotimes, sequtils, importutils, sugar, tables, times
  ]
import std/times except `getTime`
import pkg/[glm, glfw, confutils, flatty]
from pkg/glfw/wrapper import `rawMouseMotionSupported`
import
  ./[
    GlUtils, Slangc, Logger, Shapes, SceneLogic, PlayerController, CameraController,
    Math, Input, TestScenes, Containers,
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
  Config = object
    useSpirv {.
      name: "useSpirv", defaultValue: false, desc: "Use SPIR-V shaders with OpenGL"
    .}: bool
    slangBinPath {.
      name: "slangBinPath",
      defaultValue: "/opt/shader-slang-bin/bin",
      desc: "Slang shader compiler path"
    .}: string
    movementMode {.
      name: "movementMode",
      defaultValue: Flying,
      desc: "Movement mode (Flying = flying camera, Walking = FPS game controls)"
    .}: MovementMode
    mouseSensitivity {.
      name: "mouseSensitivity", defaultValue: 2.0, desc: "Mouse sensitivity"
    .}: float
    recordInputs {.
      name: "recordInputs",
      defaultValue: true,
      desc: "Record a replay buffer from player inputs"
    .}: bool
    showReplay {.
      name: "showReplay", defaultValue: "", desc: "Play back a saved replay"
    .}: string

  ActionNames = enum
    MoveFwd
    MoveBack
    MoveLeft
    MoveRight
    Jump
    FlyDown
    TurnCamera
    SetDeltaTime
    SetMonoTime

  AxisInputs = enum
    Mouse

  State = object
    conf: Config
    # Window/input
    fullscreen: bool
    monitor: Monitor
    prevWinProps: tuple[x, y, w, h, refreshRate: int]
    prevCursorX, prevCursorY: float
    # Renderer state and wrapper objects
    vertexShaderText, fragmentShaderText: string
    shader: ShaderRef
    uniforms: ShaderDataBufferRef[GpuSceneUniforms]
    vertexBuffers: seq[VertexBufferRef[ColoredVertex]]
    elementBuffers: seq[ElementBufferRef]
    vertexArrays: seq[VertexArrayRef]
    scene: Scene[ColoredVertex]
    playerI: int
    frameCount: uint64
    replayPlayer: ReplayPlayer[ActionNames]
    replayRecorder: ReplayRecorder[ActionNames]
    startTime: DateTime
    playingReplay = true

const
  shadersDir = currentSourcePath().parentDir().parentDir() / "shaders"
  appDesc = "Nim OpenGL FPS game"
  appName = "NimFpsGame"
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
  frame = FrameState()

# These templates are used as aliases for long expressions throughout this file
template cam(): untyped =
  state.scene.entities[state.playerI].camera

template player(): untyped =
  state.scene.entities[state.playerI].player

template scene(): untyped =
  state.scene

let actions: Actions[ActionNames] = {
  MoveFwd: initBoolAction(
    proc(pressed: bool) =
      player.moveDirection.z -= 1
  ),
  MoveBack: initBoolAction(
    proc(pressed: bool) =
      player.moveDirection.z += 1
  ),
  MoveLeft: initBoolAction(
    proc(pressed: bool) =
      player.moveDirection.x -= 1
  ),
  MoveRight: initBoolAction(
    proc(pressed: bool) =
      player.moveDirection.x += 1
  ),
  Jump: initBoolAction(
    proc(pressed: bool) =
      player.moveDirection.y += 1
  ),
  FlyDown: initBoolAction(
    proc(pressed: bool) =
      player.moveDirection.y -= 1
  ),
  TurnCamera: initVector2Action(
    proc(turn: Vec2f) =
      player.turnVec = turn
  ),
  SetDeltaTime: initFloatAction(
    proc(dt: float) =
      frame.deltaTime = dt,
    runOnlyWhenNonZero = false,
  ),
  SetMonoTime: initMonoTimeAction(
    proc(monoTime: MonoTime) =
      frame.monoTime = monoTime,
    runOnlyWhenNonZero = false,
  ),
}.toTable

proc updateCameraAspect(win: Window, width, height: int) =
  var ratio = width / height
  if state.playerI != 0:
    cam.aspectRatio = ratio
    cam.updateProjectionMat()

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

proc init(win: Window, useSpirV: bool) =
  state.startTime = now()
  let monitorSize = (state.monitor.workArea.w, state.monitor.workArea.h)
  state.fullscreen = win.size == monitorSize

  let date = state.startTime.format("yyyy-M-d-h-m-s")
  if state.conf.showReplay.len == 0:
    state.replayRecorder =
      initReplayRecorder[ActionNames](fmt"{date}.{$ActionNames}.replay", actions)
  else:
    state.replayPlayer = initReplayPlayer[ActionNames](state.conf.showReplay, actions)

  stdout.initGlobalLogger()

  let (width, height) = glfw.framebufferSize(win)
  win.updateCameraAspect(width, height)

  # Compile and link shader and check errors
  if not useSpirV:
    state.shader = initShaderProg(state.vertexShaderText, state.fragmentShaderText)
  else:
    state.shader = initBinShaderProg(state.vertexShaderText, state.fragmentShaderText)
  # Get used uniforms/attributes. Bare uniforms don't work in Slang so this uses UBOs.
  state.uniforms = initShaderDataBuffer[GpuSceneUniforms](
    state.shader, 0, GL_UNIFORM_BUFFER, GL_DYNAMIC_DRAW
  )

  state.playerI = scene.loadTestScene()
  player.mode = state.conf.movementMode
  player.cameraOpts.sensitivity = state.conf.mouseSensitivity

  # Set up OpenGL buffers for passing vertex data to shaders
  scene.setSceneUniforms()
  scene.makeGlBuffers()
  scene.pointLights = initShaderDataBuffer[seq[PointLight]](
    state.shader, 1, GL_SHADER_STORAGE_BUFFER, GL_DYNAMIC_DRAW
  )
  scene.loadTestSceneLights()
  scene.pointLights.upload()

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
  player.turnVec = vec2f(0)
  player.moveDirection = vec3f(0)
  if state.conf.showReplay.len <= 0:
    state.replayRecorder.recordFrameData(
      SetDeltaTime, state.frameCount, frame.deltaTime, state.conf.recordInputs
    )
    state.replayRecorder.recordFrameData(
      SetMonoTime, state.frameCount, frame.monoTime, state.conf.recordInputs
    )

    # Mouse input
    state.replayRecorder.addRecordingInputReader(
      axisActions,
      proc(a: AxisInputs): Vec2f =
        win.getAxis(a),
      state.frameCount,
      frame.deltaTime,
      state.conf.recordInputs,
    )

    # Keyboard input
    state.replayRecorder.addRecordingInputReader(
      buttonActions,
      proc(k: Key): bool =
        win.isKeyDown(k),
      state.frameCount,
      frame.deltaTime,
      state.conf.recordInputs,
    )
  else:
    if state.playingReplay:
      state.playingReplay = state.replayPlayer.play(state.frameCount)

  scene.update(frame, player.cameraOpts)

proc uninit() =
  for i in 0 .. state.vertexArrays.high:
    state.vertexBuffers[i].cleanup()
    state.elementBuffers[i].cleanup()
    state.vertexArrays[i].cleanup()
  state.uniforms.cleanup()
  state.shader.cleanup()

  state.replayRecorder.cleanup()
  if state.conf.showReplay.len > 0:
    state.replayPlayer.cleanup()

proc setUniforms(m: Model) =
  state.uniforms.modelToWorldMat = m.transform.getTransformMat()

proc setUniforms(c: CameraData)
proc draw() =
  glClearColor(0.2, 0.3, 0.3, 1.0)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

  state.shader.use()
  state.uniforms.use(state.shader)
  cam.setUniforms()

  for i in 0 .. state.vertexArrays.high:
    state.vertexArrays[i].use()
    scene.models[i].setUniforms()
    glDrawElements(
      GL_TRIANGLES, scene.models[i].indices.len, GL_UNSIGNED_INT, cast[pointer](0)
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
    let pos = $state.scene.entities[state.playerI].t.pos
    let cam = state.scene.entities[state.playerI].camera
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

proc compileShaders(useSpirV: bool, slangBinPath = "") =
  # TODO: Fields are set using setter procs here to make sure the output file field gets updated. Make the API
  # in Slangc better by adding init proc.
  var opts = SlangcOptions(entryPoint: "vertexMain")
  if not useSpirV:
    opts.target = Glsl
  else:
    opts.target = SpirV
  opts.stage = Vertex
  opts.inFile = shadersDir / "RasterizedRenderer.slang"
  if slangBinPath.len > 0:
    opts.slangPath = slangBinPath
  state.vertexShaderText = compileShaderOrRaise(opts)

  opts.stage = Fragment
  opts.entryPoint = "fragmentMain"
  state.fragmentShaderText = compileShaderOrRaise(opts)

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
  cfg.debugContext = not (defined(release) or defined(danger))
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
  glfw.swapInterval(1)
  return (win, cfg)

proc main() =
  state.conf = Config.load(copyrightBanner = appDesc)
  compileShaders(state.conf.useSpirV, state.conf.slangBinPath)

  var (win, cfg) = initGlfwAndGlad()
  win.init(state.conf.useSpirV)

  var prevFrameStart = getMonoTime()
  while not win.shouldClose:
    frame = FrameState()
    let currFrameStart = getMonoTime()
    let frameDuration = currFrameStart - prevFrameStart
    frame.deltaTime =
      frameDuration.inNanoseconds() / initDuration(seconds = 1).inNanoseconds()
    frame.monoTime = currFrameStart
    prevFrameStart = currFrameStart

    win.update()
    let updateEnd = getMonoTime()
    draw()
    glfw.swapBuffers(win)

    state.frameCount += 1
    let currFrameEnd = getMonoTime()
    logPerf(
      updateEnd - currFrameStart,
      currFrameEnd - updateEnd,
      currFrameEnd - currFrameStart,
    )

    glfw.pollEvents()
  uninit()
  glfw.terminate()

main()
