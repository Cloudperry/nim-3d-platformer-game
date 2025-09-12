import std/strformat

import ./glad/gl
import pkg/[glm, glfw]

type
  Vertex = object
    x, y: GLfloat
    r, g, b: GLfloat
  Transform = object
    pos: Vec3[float]
    scale: Vec3[float]
    rotation: Vec3[float]

const mat4x4Id = mat4f(
  vec4(1'f32, 0'f32, 0'f32, 0'f32),
  vec4(0'f32, 1'f32, 0'f32, 0'f32),
  vec4(0'f32, 0'f32, 1'f32, 0'f32),
  vec4(0'f32, 0'f32, 0'f32, 1'f32)
)

var vertices = [
  Vertex(x: -0.6, y: -0.4, r: 1.0, g: 0.0, b: 0.0),
  Vertex(x:  0.6, y: -0.4, r: 0.0, g: 1.0, b: 0.0),
  Vertex(x:  0.0, y:  0.6, r: 0.0, g: 0.0, b: 1.0) 
]

let vertexShaderText = """
#version 460
uniform mat4 MVP;
in vec3 vCol;
in vec2 vPos;
out vec3 color;

void main()
{
  gl_Position = MVP * vec4(vPos, 0.0, 1.0);
  color = vCol;
}
"""

let fragmentShaderText = """
#version 460
in vec3 color;
out vec4 fragment;

void main()
{
  fragment = vec4(color, 1.0);
}
"""

var
  program: GLuint
  mvpLocation: GLuint
  vertexArray: GLuint
  modelTransform = Transform(pos: vec3d(0, 0, 0), scale: vec3d(1, 1, 1))
  modelTransformMat = mat4x4Id

proc keyCb(win: Window, key: Key, scanCode: int32, action: KeyAction,
           modKeys: set[ModifierKey]) =

  if key == keyEscape and action == kaDown:
    win.shouldClose = true

proc getTransformMat(t: Transform): Mat4f =
  var scaleMat, translateMat, rotateMat = mat4x4Id
  # Scaling
  scaleMat[0, 0] = t.scale.x
  scaleMat[1, 1] = t.scale.y
  scaleMat[2, 2] = t.scale.z

  # Rotation
  let cx = cos(t.rotation.x)
  let sx = sin(t.rotation.x)
  let cy = cos(t.rotation.y)
  let sy = sin(t.rotation.y)
  let cz = cos(t.rotation.z)
  let sz = sin(t.rotation.z)
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

proc init() =
  var vertexBuffer: GLuint
  glGenBuffers(1, vertexBuffer.addr)
  glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer)
  glBufferData(GL_ARRAY_BUFFER, GLsizeiptr(sizeof(vertices)), vertices.addr, GL_STATIC_DRAW)

  var vertexShader = glCreateShader(GL_VERTEX_SHADER)
  var vertexShaderTextArr = [cstring(vertexShaderText)]
  glShaderSource(vertexShader, GLsizei(1), cast[cstringArray](vertexShaderTextArr.addr), nil)
  glCompileShader(vertexShader)

  var fragmentShaderTextArr = [cstring(fragmentShaderText)]
  var fragmentShader = glCreateShader(GL_FRAGMENT_SHADER)
  glShaderSource(fragmentShader, 1,
                 cast[cstringArray](fragmentShaderTextArr.addr), nil)
  glCompileShader(fragmentShader)

  program = glCreateProgram()
  glAttachShader(program, vertexShader)
  glAttachShader(program, fragmentShader)
  glLinkProgram(program)

  mvpLocation = cast[GLuint](glGetUniformLocation(program, "MVP"))
  var vposLocation = cast[GLuint](glGetAttribLocation(program, "vPos"))
  var vcolLocation = cast[GLuint](glGetAttribLocation(program, "vCol"))

  glGenVertexArrays(1, vertexArray.addr);
  glBindVertexArray(vertexArray);
  glEnableVertexAttribArray(vposLocation);
  glVertexAttribPointer(vposLocation, 2, cGL_FLOAT, false,
                        GLsizei(sizeof(Vertex)), cast[pointer](0))

  glEnableVertexAttribArray(vcolLocation)
  glVertexAttribPointer(vcolLocation, 3, cGL_FLOAT, false,
                        GLsizei(sizeof(Vertex)),
                        cast[pointer](sizeof(GLfloat) * 2));


proc draw(win: Window) =
  let normal = vec3[GLfloat](0.0, 0.0, 1.0)

  var width, height: int
  (width, height) = glfw.framebufferSize(win)

  var ratio = width / height

  glViewport(0, 0, GLsizei(width), GLsizei(height))
  glClear(GL_COLOR_BUFFER_BIT)

  modelTransform.rotation.z = getTime()
  modelTransform.rotation.x = getTime()
  var m = modelTransform.getTransformMat()
  var p = ortho[GLfloat](-ratio, ratio, -1.0, 1.0, 1.0, -1.0)
  var mvp = p * m

  glUseProgram(program)
  glUniformMatrix4fv(GLint(mvpLocation), 1, false, mvp.caddr);
  glBindVertexArray(vertexArray)
  glDrawArrays(GL_TRIANGLES, 0, 3)


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

  let m = getPrimaryMonitor()

  echo ""
  echo fmt"Monitor name:          {m.name}"
  echo fmt"Monitor content scale: {m.contentScale}"
  echo ""
  echo fmt"Window title:          {win.title}"
  echo fmt"Window frame size:     {win.frameSize}"
  echo fmt"Window content scale:  {win.contentScale}"
  echo fmt"Window opacity:        {win.opacity}"

  while not win.shouldClose:
    draw(win)

    glfw.swapBuffers(win)
    glfw.pollEvents()

  glfw.terminate()

main()
