import std/[os, strformat, options, math, monotimes, sequtils, importutils, sugar]
import std/times except `getTime`
import pkg/[glm, glfw, confutils]
from pkg/glfw/wrapper import `rawMouseMotionSupported`
import ./[GlUtils, Slangc, Logger, Shapes, SceneLogic, PlayerController, Camera, Math]
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
      name: "useSpirv", defaultValue: false, desc: "Use SPIR-V shaders with OpenGL" .}: bool
    slangBinPath {.
      name: "slangBinPath", defaultValue: "/opt/shader-slang-bin/bin", desc: "Slang shader compiler path" .}: string 
    movementMode {. 
      name: "movementMode", defaultValue: Flying, desc: "Movement mode (Flying = flying camera, Walking = FPS game controls)" .}: MovementMode
    mouseSensitivity {. 
      name: "mouseSensitivity", defaultValue: 2.0, desc: "Mouse sensitivity" .}: float
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
    pointLights: ShaderDataBufferRef[seq[PointLight]]

const
  shapeColor = vec3f(1.0'f32, 1.0'f32, 1.0'f32)
  shadersDir = currentSourcePath().parentDir().parentDir() / "shaders"
  appDesc = "Nim OpenGL FPS game"
  appName = "NimFpsGame"

var
  state = State()

proc updateCameraAspect(win: Window; width, height: int) =
  var ratio = width / height
  if state.playerI != 0:
    template c: untyped = state.scene.entities[state.playerI].camera
    case c.kind:
    of Perspective: c.setPerspective(c.verticalFov, ratio, c.nearClip, c.farClip)
    of Orthographic: c.setOrthographic(c.frustumLength, ratio, c.nearClip, c.farClip)

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
  let monitorSize = (state.monitor.workArea.w, state.monitor.workArea.h)
  state.fullscreen = win.size == monitorSize
  (state.prevCursorX, state.prevCursorY) = win.cursorPos

  stdout.initGlobalLogger()
  let
    ground = makeBox(vec3f(40.0, 0.5, 40.0), shapeColor)
    wall = makeBox(vec3f(40.0, 7, 1.0), shapeColor)
    cube = makeBox(vec3f(0.5), shapeColor)
    pyramid = makePyramid(0.5'f32, shapeColor)
    sphere = makeSphere(0.5, 100, 100, shapeColor)
    groundModel = initModel(
      ground.vertices, ground.indices, transform = Transform(pos: vec3f(0, -2, 0), scale: vec3f(1, 1, 1))
    )
    wallModel = initModel(
      wall.vertices, wall.indices, transform = Transform(pos: vec3f(0, 1.5, -39), scale: vec3f(1, 1, 1))
    )
    groundModelLowerLv = initModel(
      ground.vertices, ground.indices, transform = Transform(pos: vec3f(0, -5, 40), scale: vec3f(1, 1, 1))
    )
    roofModel = initModel(
      ground.vertices, ground.indices, transform = Transform(pos: vec3f(0, 5, 0), scale: vec3f(1, 1, 1))
    )
    cubeModel = initModel(
      cube.vertices, cube.indices, transform = Transform(pos: vec3f(0, 0, -2), scale: vec3f(1, 1, 1))
    )
    pyramidModel = initModel(
      pyramid.vertices, pyramid.indices, transform = Transform(pos: vec3f(-2, 0, -2), scale: vec3f(1, 1, 1))
    )
    sphereModel = initModel(
      sphere.vertices, sphere.indices, transform = Transform(pos: vec3f(2, 0, -2), scale: vec3f(1, 1, 1))
    )

  let (width, height) = glfw.framebufferSize(win)
  win.updateCameraAspect(width, height)

  state.scene = initScene(
    @[groundModel, wallModel, groundModelLowerLv, roofModel, cubeModel, pyramidModel, sphereModel],
    DirectionalLight(direction: vec3f(-5, -5, -3).normalize(), color: vec3f(0.7, 0.35, 0.25)).some,
    vec3f(0.1).some
  )
  discard state.scene.addEntity initBoxColliderE(
    Transform(pos: vec3f(0.0, -2.0, 0.0)),
    BoxColliderData(
      halfExtents: vec3f(40, 0.5, 40),
      tags: {Ground}
    )
  )
  discard state.scene.addEntity initBoxColliderE(
    Transform(pos: vec3f(0.0, -5.0, 40.0)),
    BoxColliderData(
      halfExtents: vec3f(40, 0.5, 40),
      tags: {Ground}
    )
  )
  discard state.scene.addEntity initBoxColliderE(
    Transform(pos: vec3f(0.0, 1.5, -39.0)),
    BoxColliderData(halfExtents: vec3f(40, 7, 1))
  )

  # Set camera options to defaults. Mouse sensitivity is fast on a gaming mouse, but might be too slow for a normal mouse.
  var cam = initPerspectiveCamera(80, 150 / 100, 0.1, 100, true)
  let collider = BoxColliderData(halfExtents: vec3f(0.25, 2.0, 0.25))
  var playerE = initPlayerE(Transform(pos: vec3f(0, 1, 0)), PlayerData(), cam, collider)

  playerE.updateTransform()
  playerE.player.mode = state.conf.movementMode
  playerE.player.cameraOpts = FpCameraOptions()
  playerE.player.cameraOpts.sensitivity = state.conf.mouseSensitivity

  state.playerI = state.scene.addEntity playerE

  # Compile and link shader and check errors
  if not useSpirV:
    state.shader = initShaderProg(state.vertexShaderText, state.fragmentShaderText)
  else:
    state.shader = initBinShaderProg(state.vertexShaderText, state.fragmentShaderText)
  # Get used uniforms/attributes. Bare uniforms don't work in Slang so this uses UBOs.
  state.uniforms = initShaderDataBuffer[GpuSceneUniforms](state.shader, 0, GL_UNIFORM_BUFFER, GL_DYNAMIC_DRAW)

  # Set up OpenGL buffers for passing vertex data to shaders
  state.scene.makeGlBuffers()
  state.scene.setSceneUniforms()
  state.pointLights = initShaderDataBuffer[seq[PointLight]](state.shader, 1, GL_SHADER_STORAGE_BUFFER, GL_DYNAMIC_DRAW)
  state.pointLights.add PointLight(
    position: vec3f(3, 0, 3), color: vec3f(0.8, 0.4, 0),
    constTerm: 1, linearFalloff: 0.5, expFalloff: 1/20
  )
  state.pointLights.add PointLight(
    position: vec3f(-3, 0, 3), color: vec3f(0, 0.5, 0.7),
    constTerm: 1, linearFalloff: 0.5, expFalloff: 1/20
  )
  state.pointLights.add PointLight(
    position: vec3f(0, 0, -5), color: vec3f(0.4, 0.4, 0.4),
    constTerm: 1, linearFalloff: 0.5, expFalloff: 1/20
  )
  state.pointLights.upload()

  # Enable backface culling
  glEnable(GL_CULL_FACE)
  glCullFace(GL_BACK)
  glFrontFace(GL_CCW)

  # Enable depth buffer to for correct occlusion when rendering multiple objects 
  glEnable(GL_DEPTH_TEST)
  glDepthFunc(GL_LESS)

proc update(win: Window, frame: var FrameState) =
  let cursorPos = win.cursorPos
  (frame.cursorDeltaX, frame.cursorDeltaY) = (cursorPos.x - state.prevCursorX, cursorPos.y - state.prevCursorY)
  (state.prevCursorX, state.prevCursorY) = cursorPos

  # Keyboard input
  frame.moveDirection = vec3f(0)
  if win.isKeyDown(keyComma) or win.isKeyDown(keyW):
    frame.moveDirection.z -= 1
  elif win.isKeyDown(keyO) or win.isKeyDown(keyS):
    frame.moveDirection.z += 1
  if win.isKeyDown(keyE) or win.isKeyDown(keyD):
    frame.moveDirection.x += 1
  elif win.isKeyDown(keyA):
    frame.moveDirection.x -= 1
  if win.isKeyDown(keySpace):
    frame.moveDirection.y += 1
  elif win.isKeyDown(keyBackslash) or win.isKeyDown(keyLeftShift):
    frame.moveDirection.y -= 1

  template p: untyped = state.scene.entities[state.playerI]
  state.scene.update(frame, p.player.cameraOpts)

proc uninit() =
  for i in 0 .. state.vertexArrays.high:
    state.vertexBuffers[i].cleanup()
    state.elementBuffers[i].cleanup()
    state.vertexArrays[i].cleanup()
  state.uniforms.cleanup()
  state.shader.cleanup()

proc setUniforms(m: Model) =
  state.uniforms.modelToWorldMat = m.transform.getTransformMat()

proc setUniforms(c: CameraData)
proc draw(win: Window) =
  glClearColor(0.2, 0.3, 0.3, 1.0)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

  state.shader.use()
  state.uniforms.use(state.shader)
  state.scene.entities[state.playerI].camera.setUniforms()

  for i in 0 .. state.vertexArrays.high:
    state.vertexArrays[i].use()
    state.scene.models[i].setUniforms()
    glDrawElements(GL_TRIANGLES, state.scene.models[i].indices.len, GL_UNSIGNED_INT, cast[pointer](0))

proc sizeCb(win: Window, size: tuple[w, h: int32]) = win.updateCameraAspect(size.w, size.h)

proc setUniforms(c: CameraData) =
  state.uniforms.worldToViewMat = c.viewMat
  state.uniforms.viewToClipMat = c.projectionMat

proc keyCb(win: Window, key: Key, scanCode: int32, action: KeyAction, modKeys: set[ModifierKey]) =
  if key == keyEscape and action == kaDown:
    win.shouldClose = true
  elif (key == keyLeftAlt and win.isKeyDown(keyEnter) or
  key == keyEnter and win.isKeyDown(keyLeftAlt)) and action == kaDown:
    if not state.fullscreen:
      let monitorArea = state.monitor.workArea()
      let monitorMode = state.monitor.videoMode()
      state.prevWinProps = (win.pos.x, win.pos.y, win.size.w, win.size.h, monitorMode.refreshRate)
      globalLogger.log fmt"Going into fullscreen {(monitorArea.x, monitorArea.y, monitorArea.w, monitorArea.h, monitorMode.refreshRate)}"
      win.monitor = (state.monitor, monitorArea.x, monitorArea.y, monitorArea.w, monitorArea.h, monitorMode.refreshRate)
    else:
      let winProps = (state.prevWinProps.x, state.prevWinProps.y, state.prevWinProps.w, state.prevWinProps.h, state.prevWinProps.refreshRate)
      globalLogger.log fmt"Going out of fullscreen {winProps}"
      win.monitor = (
        newMonitor(nil), state.prevWinProps.x, state.prevWinProps.y,
        state.prevWinProps.w, state.prevWinProps.h, state.prevWinProps.refreshRate
      )
    state.fullscreen = not state.fullscreen

  # TODO: Camera is not getting updated using the window size callback on fullscreen. This is a hack to update it.
  # Find out why size callbacks don't fire on fullscreen.
  let (width, height) = glfw.framebufferSize(win)
  win.updateCameraAspect(width, height)

proc positionCb(win: Window, pos: tuple[x, y: int32]) =
  let newMonitor = win.monitor
  privateAccess(newMonitor.type)
  if newMonitor.handle != nil: # Linux Wayland sometimes gave nil monitors for win.monitor, check that its not nil
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
  if slangBinPath.len > 0: opts.slangPath = slangBinPath
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

  glfw.swapInterval(1)
  return (win, cfg)

proc main() =
  state.conf = Config.load(copyrightBanner=appDesc)
  compileShaders(state.conf.useSpirV, state.conf.slangBinPath)

  var (win, cfg) = initGlfwAndGlad()
  win.init(state.conf.useSpirV)

  var frame = FrameState()
  var prevFrameStart = getMonoTime()
  while not win.shouldClose:
    frame = FrameState()
    let currFrameStart = getMonoTime()
    let frameDuration = currFrameStart - prevFrameStart
    frame.deltaTime = frameDuration.inNanoseconds() / initDuration(seconds = 1).inNanoseconds()
    frame.monoTime = currFrameStart
    prevFrameStart = currFrameStart
    
    win.update(frame)
    let updateEnd = getMonoTime()
    win.draw()
    glfw.swapBuffers(win)

    let currFrameEnd = getMonoTime()
    logPerf(updateEnd - currFrameStart, currFrameEnd - updateEnd, currFrameEnd - currFrameStart)

    glfw.pollEvents()
  uninit()
  glfw.terminate()

main()