import std/[os, strformat, options, math, monotimes, sequtils, importutils, sugar]
import std/times except `getTime`
import pkg/[glm, glfw, cligen]
from pkg/glfw/wrapper import `rawMouseMotionSupported`
import ./glad/gl
import GlUtils, Slangc, Scene, Logger, Shapes, SdfScene

type
  RendererMode = enum
    Rasterizer, SdfRenderer
  EngineState = object
    mode: RendererMode
    # Window/input
    fullscreen: bool
    monitor: Monitor
    prevWinProps: tuple[x, y, w, h, refreshRate: int]
    cameraOpts: FpCameraOptions
    prevCursorX, prevCursorY: float
    # Graphics
    vertexShaderText, fragmentShaderText: string
    camera: RasterizedCamera
  FrameState = object
    cursorDeltaX, cursorDeltaY, deltaTime: float

const
  shapeColor = vec3f(1.0)
  shadersDir = currentSourcePath().parentDir().parentDir() / "shaders"

var
  state = EngineState()
  logger = Logger()

proc initSharedState(win: Window, mode: RendererMode) =
  state.mode = mode
  let monitorSize = (state.monitor.workArea.w, state.monitor.workArea.h)
  state.fullscreen = win.size == monitorSize
  (state.prevCursorX, state.prevCursorY) = win.cursorPos

  # Set camera options to defaults. Mouse sensitivity is fast on a gaming mouse, but might be too slow for a normal mouse.
  state.cameraOpts = FpCameraOptions()
  state.camera = initPerspectiveCamera(80, 150 / 100, 0.1, 100, mode == Rasterizer)
  state.camera.pos = vec3f(0, 0, 0)
  state.camera.updateTransform()

  logger = stdout.initLogger()

proc commonUpdate(win: Window, frame: var FrameState) =
  let cursorPos = win.cursorPos
  (frame.cursorDeltaX, frame.cursorDeltaY) = (cursorPos.x - state.prevCursorX, cursorPos.y - state.prevCursorY)
  (state.prevCursorX, state.prevCursorY) = cursorPos

  # Keyboard input
  var moveDirection = vec3f(0)
  if win.isKeyDown(keyComma):
    moveDirection.z -= 1
  elif win.isKeyDown(keyO):
    moveDirection.z += 1
  if win.isKeyDown(keyE):
    moveDirection.x += 1
  elif win.isKeyDown(keyA):
    moveDirection.x -= 1
  if win.isKeyDown(keySpace):
    moveDirection.y += 1
  elif win.isKeyDown(keyBackslash):
    moveDirection.y -= 1

  state.camera.doFirstPersonCameraMovement(
    state.cameraOpts, moveDirection, frame.cursorDeltaX, frame.cursorDeltaY, frame.deltaTime
  )

# ======================================== Rasterizer ========================================
makeGlObjects(std140Alignment, RaiseError):
  type GpuSceneUniforms = object
    cameraPos: Vec3f
    # Just one model to world transform for now, separate transforms for each model will be needed later
    modelToWorldMat, worldToViewMat, viewToClipMat: Mat4f 
    mainLightDirection: Vec3f
    mainLightColor: Vec3f
    ambientLightColor: Vec3f

type 
  RasterizerState = object
    # Renderer state and wrapper objects
    shader: ShaderRef
    uniforms: ShaderDataBufferRef[GpuSceneUniforms]
    vertexBuffers: seq[VertexBufferRef[ColoredVertex]]
    elementBuffers: seq[ElementBufferRef]
    vertexArrays: seq[VertexArrayRef]
    scene: Scene[ColoredVertex]

var rasterizer = RasterizerState()

proc updateCameraAspect(win: Window; width, height: int) =
  var ratio = width / height
  case state.camera.kind
  of Perspective: state.camera.setPerspective(
    state.camera.verticalFov, ratio, state.camera.nearClip, state.camera.farClip
  )
  of Orthographic: state.camera.setOrthographic(
    state.camera.frustumLength, ratio, state.camera.nearClip, state.camera.farClip
  )

  glViewport(0, 0, width, height)

proc makeGlBuffers[T](s: Scene[T]) =
  rasterizer.vertexBuffers.setLen s.models.len
  rasterizer.elementBuffers.setLen s.models.len
  rasterizer.vertexArrays.setLen s.models.len

  for i, model in s.models:
    rasterizer.vertexBuffers[i] = initVertexBuffer (model.vertices, GL_STATIC_DRAW).some
    rasterizer.elementBuffers[i] = initElementBuffer (model.indices, GL_STATIC_DRAW).some
    rasterizer.vertexArrays[i] = initVertexArray()
    rasterizer.vertexArrays[i].use()
    rasterizer.vertexBuffers[i].use()
    rasterizer.vertexArrays[i].attachElementBuffer(rasterizer.elementBuffers[i])

proc setSceneUniforms[T](s: Scene[T]) =
  rasterizer.uniforms.setField(mainLightDirection, s.dirLight.direction)
  rasterizer.uniforms.setField(mainLightColor, s.dirLight.color)
  rasterizer.uniforms.setField(ambientLightColor, s.ambientLightColor)

proc initRasterizer(win: Window) =
  let
    cube = makeCube(shapeColor)
    pyramid = makePyramid(shapeColor)
    sphere = makeSphere(0.5, 16, 16, shapeColor)
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

  rasterizer.scene = initScene(
    state.camera,
    @[cubeModel, pyramidModel, sphereModel],
    DirectionalLight(direction: vec3f(-5, -5, -3).normalize(), color: vec3f(1, 0.6, 0.3)).some,
    vec3f(0.1).some
  )

  # Compile and link shader and check errors
  rasterizer.shader = initShaderProg(state.vertexShaderText, state.fragmentShaderText)
  # Get used uniforms/attributes. Bare uniforms don't work in Slang so this uses UBOs.
  rasterizer.uniforms = initShaderDataBuffer[GpuSceneUniforms](rasterizer.shader, 0, GL_UNIFORM_BUFFER, GL_DYNAMIC_DRAW)

  # Set up OpenGL buffers for passing vertex data to shaders
  rasterizer.scene.makeGlBuffers()
  rasterizer.scene.setSceneUniforms()

  # Enable backface culling
  glEnable(GL_CULL_FACE)
  glCullFace(GL_BACK)
  glFrontFace(GL_CCW)

  # Enable depth buffer to for correct occlusion when rendering multiple objects 
  glEnable(GL_DEPTH_TEST)
  glDepthFunc(GL_LESS)

proc uninitRasterizer() =
  for i in 0 .. rasterizer.vertexArrays.high:
    rasterizer.vertexBuffers[i].cleanup()
    rasterizer.elementBuffers[i].cleanup()
    rasterizer.vertexArrays[i].cleanup()
  rasterizer.uniforms.cleanup()
  rasterizer.shader.cleanup()

proc updateRasterizer(win: Window, frame: FrameState) =
  discard

proc setUniforms(m: Model) =
  rasterizer.uniforms.setField(modelToWorldMat, m.transform.getTransformMat())

proc setUniforms(c: RasterizedCamera)
proc drawRasterizer(win: Window) =
  glClearColor(0.2, 0.3, 0.3, 1.0)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

  rasterizer.shader.use()
  rasterizer.uniforms.use(rasterizer.shader)
  state.camera.setUniforms()

  for i in 0 .. rasterizer.vertexArrays.high:
    rasterizer.vertexArrays[i].use()
    rasterizer.scene.models[i].setUniforms()
    glDrawElements(GL_TRIANGLES, rasterizer.scene.models[i].indices.len, GL_UNSIGNED_INT, cast[pointer](0))

proc sizeCbRasterizer(win: Window, size: tuple[w, h: int32]) = win.updateCameraAspect(size.w, size.h)

# ======================================== SDF renderer (sphere tracer) ========================================
type RenderMode {.size: sizeof(uint32).} = enum
  ShadedScene, UnlitScene, DebugNormals, DebugStepCounts
makeGlObjects(std140Alignment, RaiseError):
  type GpuSdfSceneUniforms = object
    aspect: GLfloat 
    camPos, camForward, camRight, camUp, hitColor, bgColor: Vec3f
    fov: GLfloat
  type DebugSettings = object
    mode: RenderMode

type
  ScreenSpaceVertex = object
    pos, uv: Vec2f
  # TODO: Move camera data in this object (possibly using the existing camera class, but without rasterization specific stuff).
  # Set uniforms by making a function that uses the camera class data.
  SdfRendererState = object
    shader: ShaderRef
    sceneUbo: ShaderDataBufferRef[GpuSdfSceneUniforms]
    debugOptUbo: ShaderDataBufferRef[DebugSettings]
    sceneProgramData: ShaderDataBufferRef[SdfProgramData]
    sceneProgram: ShaderDataBufferRef[seq[SdfInstruction]]
    sceneBuilder: SceneBuilder
    imagePlaneVbo: VertexBufferRef[ScreenSpaceVertex]
    imagePlaneVao: VertexArrayRef
    dynamicCutter: tuple[outputI: ParamIndex, instI: int]

var sdfRenderer = SdfRendererState()

proc updateCameraAspect(width, height: int) =
  glViewport(0, 0, width, height)

proc initSdfRenderer(win: Window) =
  let (width, height) = glfw.framebufferSize(win)
  updateCameraAspect(width, height)

  sdfRenderer.shader = initShaderProg(state.vertexShaderText, state.fragmentShaderText)
  sdfRenderer.sceneUbo = initShaderDataBuffer[GpuSdfSceneUniforms](sdfRenderer.shader, 0, GL_UNIFORM_BUFFER, GL_DYNAMIC_DRAW)
  # This could probably be GL_STATIC_DRAW as its updated veery rarely, but OpenGL complained when updating it
  sdfRenderer.debugOptUbo = initShaderDataBuffer[DebugSettings](sdfRenderer.shader, 1, GL_UNIFORM_BUFFER, GL_DYNAMIC_DRAW)
  sdfRenderer.sceneProgramData = initShaderDataBuffer[SdfProgramData](sdfRenderer.shader, 0, GL_SHADER_STORAGE_BUFFER, GL_STATIC_DRAW, data = SdfProgramData().some)
  sdfRenderer.sceneProgram = initShaderDataBuffer[seq[SdfInstruction]](sdfRenderer.shader, 1, GL_SHADER_STORAGE_BUFFER, GL_STATIC_DRAW, data = emptySdfProgram().some)
  sdfRenderer.sceneBuilder = initSceneBuilder(sdfRenderer.sceneProgramData.data, sdfRenderer.sceneProgram.data)

  let innerBox = sdfRenderer.sceneBuilder.addRoundBox(vec3f(0, 0, 0), vec3f(9, 3, 9), 0.5).outputI
  let outerBox = sdfRenderer.sceneBuilder.addBox(vec3f(0, 0, 0), vec3f(10, 5, 10)).outputI
  let windowNorth = sdfRenderer.sceneBuilder.addBox(vec3f(0, 0, -9), vec3f(1.5, 1.5, 2)).outputI
  var room = sdfRenderer.sceneBuilder.cut(innerBox, outerBox).outputI
  sdfRenderer.dynamicCutter = sdfRenderer.sceneBuilder.addBox(vec3f(0), vec3f(1.5))
  room = sdfRenderer.sceneBuilder.cut(windowNorth, room).outputI
  discard sdfRenderer.sceneBuilder.cut(sdfRenderer.dynamicCutter.outputI, room)

  let vertices = @[
    ScreenSpaceVertex(pos: vec2f(-1.0, -1.0), uv: vec2f(0.0, 0.0)), # Bottom left
    ScreenSpaceVertex(pos: vec2f(1.0, -1.0), uv: vec2f(1.0, 0.0)), # Bottom right
    ScreenSpaceVertex(pos: vec2f(1.0, 1.0), uv: vec2f(1.0, 1.0)), # Top right
    ScreenSpaceVertex(pos: vec2f(-1.0, 1.0), uv: vec2f(0.0, 1.0)) # Top left
  ]
  let imagePlaneTriangles = @[
    vertices[0], vertices[1], vertices[2],
    vertices[0], vertices[2], vertices[3]
  ]

  sdfRenderer.imagePlaneVbo = initVertexBuffer (imagePlaneTriangles, GL_STATIC_DRAW).some
  sdfRenderer.imagePlaneVao = initVertexArray()
  sdfRenderer.imagePlaneVao.use()
  sdfRenderer.imagePlaneVbo.use()

proc uninitSdfRenderer() =
  sdfRenderer.imagePlaneVbo.cleanup()
  sdfRenderer.imagePlaneVao.cleanup()
  sdfRenderer.sceneUbo.cleanup()
  sdfRenderer.shader.cleanup()

proc updateSdfRenderer(win: Window, frame: FrameState) =
  let inst = sdfRenderer.sceneProgram.data[sdfRenderer.dynamicCutter.instI]
  let newX: float32 = sin(glfw.getTime().float32 * 0.8) * 10
  sdfRenderer.sceneProgramData.data.params[inst.argsIndex.uint32] = cast[uint32](newX)

proc setUniforms(c: RasterizedCamera) =
  if c.rasterizerOn:
    rasterizer.uniforms.setField(worldToViewMat, c.viewMat)
    rasterizer.uniforms.setField(viewToClipMat, c.projectionMat)
  else:
    sdfRenderer.sceneUbo.setField(camPos, c.pos)
    sdfRenderer.sceneUbo.setField(camForward, c.forward)
    sdfRenderer.sceneUbo.setField(camRight, c.right)
    sdfRenderer.sceneUbo.setField(camUp, c.up)

proc drawSdfRenderer(win: Window) =
  glClearColor(0.2, 0.3, 0.3, 1.0)
  glClear(GL_COLOR_BUFFER_BIT)
  
  sdfRenderer.shader.use()
  sdfRenderer.sceneUbo.use(sdfRenderer.shader)
  # TODO: Move this into the appropriate callback
  let (width, height) = glfw.framebufferSize(win)
  sdfRenderer.sceneUbo.setField(aspect, width / height)
  sdfRenderer.sceneUbo.setField(hitColor, vec3f(1, 1, 1))
  sdfRenderer.sceneUbo.setField(bgColor, vec3f(0.2, 0.3, 0.3))
  sdfRenderer.sceneUbo.setField(fov, 80)
  state.camera.setUniforms()

  sdfRenderer.imagePlaneVao.use()
  sdfRenderer.sceneProgramData.upload()
  sdfRenderer.sceneProgram.upload()
  glDrawArrays(GL_TRIANGLES, 0, 6)

proc sizeCbSdfRenderer(win: Window, size: tuple[w, h: int32]) = 
  updateCameraAspect(size.w, size.h)

proc keyCb(win: Window, key: Key, scanCode: int32, action: KeyAction, modKeys: set[ModifierKey]) =
  if key == keyEscape and action == kaDown:
    win.shouldClose = true
  elif (key == keyLeftAlt and win.isKeyDown(keyEnter) or
  key == keyEnter and win.isKeyDown(keyLeftAlt)) and action == kaDown:
    if not state.fullscreen:
      let monitorArea = state.monitor.workArea()
      let monitorMode = state.monitor.videoMode()
      state.prevWinProps = (win.pos.x, win.pos.y, win.size.w, win.size.h, monitorMode.refreshRate)
      logger.log fmt"Going into fullscreen {(monitorArea.x, monitorArea.y, monitorArea.w, monitorArea.h, monitorMode.refreshRate)}"
      win.monitor = (state.monitor, monitorArea.x, monitorArea.y, monitorArea.w, monitorArea.h, monitorMode.refreshRate)
    else:
      let winProps = (state.prevWinProps.x, state.prevWinProps.y, state.prevWinProps.w, state.prevWinProps.h, state.prevWinProps.refreshRate)
      logger.log fmt"Going out of fullscreen {winProps}"
      win.monitor = (
        newMonitor(nil), state.prevWinProps.x, state.prevWinProps.y,
        state.prevWinProps.w, state.prevWinProps.h, state.prevWinProps.refreshRate
      )
    state.fullscreen = not state.fullscreen

  # TODO: Camera is not getting updated using the window size callback on fullscreen. This is a hack to update it.
  # Find out why size callbacks don't fire on fullscreen.
  let (width, height) = glfw.framebufferSize(win)
  case state.mode
  of Rasterizer:
    win.updateCameraAspect(width, height)
  of SdfRenderer:
    # SDF debug keybinds
    if key == keyF1 and action == kaDown:
      sdfRenderer.debugOptUbo.setField(mode, ShadedScene)
    elif key == keyF2 and action == kaDown:
      sdfRenderer.debugOptUbo.setField(mode, UnlitScene)
    elif key == keyF3 and action == kaDown:
      sdfRenderer.debugOptUbo.setField(mode, DebugNormals)
    elif key == keyF4 and action == kaDown:
      sdfRenderer.debugOptUbo.setField(mode, DebugStepCounts)
    updateCameraAspect(width, height)

proc positionCb(win: Window, pos: tuple[x, y: int32]) =
  let newMonitor = win.monitor
  privateAccess(newMonitor.type)
  if newMonitor.handle != nil: # Linux Wayland sometimes gave nil monitors for win.monitor, check that its not nil
    state.monitor = newMonitor

proc compileShaders(slangPath = "", mode: RendererMode) =
  let shaderFile = case mode
  of Rasterizer: "RasterizedRenderer.slang"
  of SdfRenderer: "SdfRenderer.slang"
  
  # TODO: Fields are set using setter procs here to make sure the output file field gets updated. Make the API better by adding init proc.
  var opts = SlangcOptions(entryPoint: "vertexMain")
  opts.stage = Vertex
  opts.inFile = shadersDir / shaderFile
  opts.target = Glsl
  if slangPath.len > 0: opts.slangPath = slangPath
  state.vertexShaderText = compileShaderOrRaise(opts)

  opts.stage = Fragment
  opts.entryPoint = "fragmentMain"
  state.fragmentShaderText = compileShaderOrRaise(opts)

proc initGlfwAndGlad(mode: RendererMode): tuple[win: Window, cfg: OpenglWindowConfig] =
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
  if mode == Rasterizer:
    cfg.bits.depth = 24.some

  # GLFW init that has to be done after window creation
  var win = newWindow(cfg)
  if not gladLoadGL(getProcAddress):
    quit "Error initialising OpenGL"
  if cfg.debugContext: # Enable debug logging when using an OpenGL debug context
    setupGlDebugLogging()

  win.keyCb = keyCb
  case mode
  of Rasterizer: win.windowSizeCb = sizeCbRasterizer
  of SdfRenderer: win.windowSizeCb = sizeCbSdfRenderer
  win.windowPositionCb = positionCb
  win.aspectRatio = (3, 2)
  win.cursorMode = cmDisabled
  state.monitor = getPrimaryMonitor()

  if rawMouseMotionSupported() != 0:
    win.rawMouseMotion = true
  else:
    logger.log "Raw mouse motion not supported. Camera rotation speed will be dependent on desktop mouse settings."

  glfw.swapInterval(1)
  return (win, cfg)

# This is done to avoid branching within the main loop, while still allowing runtime selection between rasterizer and SDF renderer
proc updateDrawLoop(win: Window, frame: var FrameState; updateProc, drawProc: proc) =
  var prevFrameStart = getMonoTime()
  while not win.shouldClose:
    frame = FrameState()
    let currFrameStart = getMonoTime()
    let frameDuration = currFrameStart - prevFrameStart
    frame.deltaTime = frameDuration.inNanoseconds() / initDuration(seconds = 1).inNanoseconds()
    prevFrameStart = currFrameStart
    win.commonUpdate(frame)
    
    updateProc()
    let updateEnd = getMonoTime()
    drawProc()
    glfw.swapBuffers(win)
    let currFrameEnd = getMonoTime()
    logger.logPerf(updateEnd - currFrameStart, currFrameEnd - updateEnd, currFrameEnd - currFrameStart)

    glfw.pollEvents()

proc main(slangPath: string = "", mode: RendererMode = Rasterizer) =
  compileShaders(slangPath, mode)

  var (win, cfg) = initGlfwAndGlad(mode)
  win.initSharedState(mode)
  case mode
  of Rasterizer: win.initRasterizer()
  of SdfRenderer: win.initSdfRenderer()

  var frame = FrameState()
  case mode
  of Rasterizer: 
    updateDrawLoop(
      win, frame,
      () => win.updateRasterizer(frame),
      () => win.drawRasterizer()
    )
  of SdfRenderer:
    updateDrawLoop(
      win, frame,
      () => win.updateSdfRenderer(frame),
      () => win.drawSdfRenderer()
    )

  case mode
  of Rasterizer: uninitRasterizer()
  of SdfRenderer: uninitSdfRenderer()
  glfw.terminate()

when isMainModule:
  dispatch main
