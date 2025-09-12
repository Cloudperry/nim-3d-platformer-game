import std/[os, strformat, options]

import pkg/[glm, glfw]
import ./glad/gl
import GlUtils, Slangc

type
  ColoredVertex = object
    pos, color: Vec3f
  ColorUbo = object
    myColor: GLfloat

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
  vertices = @[
    ColoredVertex(pos: vec3f(0.5, 0.5, 0.0), color: vec3f(1.0, 0.0, 0.0)), # top right
    ColoredVertex(pos: vec3f(0.5, -0.5, 0.0), color: vec3f(0.0, 1.0, 0.0)), # bottom right
    ColoredVertex(pos: vec3f(-0.5, -0.5, 0.0), color: vec3f(0.0, 0.0, 1.0)), # bottom left
    ColoredVertex(pos: vec3f(-0.5,  0.5, 0.0), color: vec3f(0.0, 1.0, 1.0)) # top left
  ]
  indices: seq[GLuint] = @[
    0, 1, 3,
    1, 2, 3
  ]
  shader: ShaderRef
  uniforms: ShaderStorageRef[ColorUbo]
  vbo: VertexBufferRef[ColoredVertex]
  vao: VertexArrayRef
  ebo: ElementBufferRef

proc keyCb(win: Window, key: Key, scanCode: int32, action: KeyAction, modKeys: set[ModifierKey]) =
  if key == keyEscape and action == kaDown:
    win.shouldClose = true

proc init() =
  shader = initShaderProg(vertexShaderText, fragmentShaderText)
  # Get used uniforms/attributes. Bare uniforms don't work in Slang so this uses UBOs.
  uniforms = initShaderStorage[ColorUbo](shader, GL_DYNAMIC_DRAW, 0)

  vbo = initVertexBuffer (vertices, GL_STATIC_DRAW).some
  ebo = initElementBuffer (indices, GL_STATIC_DRAW).some
  vao = initVertexArray()
  vao.use()
  vbo.use()
  vao.attachElementBuffer(ebo)

proc uninit() =
  vao.cleanup() # TODO: Test if messy VAO abstraction explodes by calling vbo.cleanup or ebo.cleanup before this
  uniforms.cleanup()
  shader.cleanup()

proc draw(win: Window) =
  var (width, height) = glfw.framebufferSize(win)
  var ratio = width / height

  glViewport(0, 0, width, height)
  glClearColor(0.2, 0.3, 0.3, 1.0)
  glClear(GL_COLOR_BUFFER_BIT)
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

  shader.use()
  uniforms.uploadField(uniforms.data, myColor):
    uniforms.data.myColor = sin(getTime()) / 2.0 + 0.5
  uniforms.use(shader)
  vao.use()
  glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, cast[pointer](0))

proc main() =
  glfw.initialize()

  var cfg = DefaultOpenglWindowConfig
  cfg.size = (w: 640, h: 480)
  cfg.title = "Simple example"
  cfg.resizable = true
  cfg.version = glv46
  cfg.forwardCompat = true
  cfg.profile = opCoreProfile

  var win = newWindow(cfg)

  win.keyCb = keyCb

  if not gladLoadGL(getProcAddress):
    quit "Error initialising OpenGL"

  glfw.swapInterval(1)

  init()

  win.pos = (150, 100)
  win.aspectRatio = (3, 2)
  win.sizeLimits = (300, 200, 1200, 800)

  while not win.shouldClose:
    draw(win)

    glfw.swapBuffers(win)
    glfw.pollEvents()

  uninit()
  glfw.terminate()

main()
