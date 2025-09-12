import std/[tables, strformat, options, sequtils]
import ./glad/gl
import pkg/glm

proc checkError*(shader: GLuint) =
  var code: GLint
  glGetShaderiv(shader, GL_COMPILE_STATUS, addr code)
  if code.GLboolean == GL_FALSE.GLboolean:
    var length: GLint = 0
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, addr length)
    var log = newString(length.int)
    glGetShaderInfoLog(shader, length, nil, log.cstring)
    echo log

proc checkLinkError*(program: GLuint) =
  var code: GLint
  glGetProgramiv(program, GL_LINK_STATUS, addr code)
  if code.GLboolean == GL_FALSE.GLboolean:
    var length: GLint = 0
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, addr length)
    var log = newString(length.int)
    glGetProgramInfoLog(program, length, nil, log.cstring)
    echo log

proc glShaderSourceStr*(shader: GLuint, count: GLsizei, s: string, length: ptr GLint) = # Probably doesn't need a wrapper, converter is enough
  var arr = [cstring(s)]
  glShaderSource(shader, count, cast[cstringArray](addr arr), length)

converter toGlSizeIPtr*(n: int): GLsizeiptr = GLsizeiptr(n)
converter toGlSizeI*(n: int): GLsizei = GLsizei(n)
converter toGlUint*(n: int): GLuint = GLuint(n)
converter toGlInt*(n: int): GLint = GLint(n)
converter toCstringArray(s: string): cstringArray {.inline.} =
  let arr = [cstring(s)]
  return cast[cstringArray](addr arr)

type ShaderRef* = ref object
  id: GLuint

proc initShaderProg*(vertexSrc: string, fragmentSrc: string): ShaderRef =
  result = new ShaderRef

  # Compile shaders
  let vertexShader: GLuint = glCreateShader(GL_VERTEX_SHADER)
  var fragmentShader: GLuint = glCreateShader(GL_FRAGMENT_SHADER)
  glShaderSourceStr(vertexShader, 1, vertexSrc, nil)
  glCompileShader(vertexShader)
  checkError(vertexShader)
  glShaderSourceStr(fragmentShader, 1, fragmentSrc, nil)
  glCompileShader(fragmentShader)
  checkError(fragmentShader)

  # Link and clean up
  result.id = glCreateProgram()
  glAttachShader(result.id, vertexShader)
  glAttachShader(result.id, fragmentShader)
  glLinkProgram(result.id)
  checkLinkError(result.id)
  glDeleteShader(vertexShader)
  glDeleteShader(fragmentShader)

proc use*(s: ShaderRef) = glUseProgram(s.id)
template withShader*(s: ShaderRef, body: untyped) =
  s.use()
  body
  glUseProgram(0)

proc cleanup*(s: var ShaderRef) =
  glDeleteProgram(s.id)
  s = nil
proc `=dispose`*(s: var ShaderRef) = s.cleanup()

type ShaderStorageRef*[T] = ref object
  id: GLuint
  storageType: GLenum
  shaderSlots: Table[GLuint, int]
  data*: T

proc initShaderStorage*[T](targetShader: ShaderRef, storageType: GLenum, shaderSlot: int, data: Option[T] = T.none): ShaderStorageRef[T] = 
  result = new ShaderStorageRef[T]
  result.shaderSlots = initTable[GLuint, int]()
  result.shaderSlots[targetShader.id] = shaderSlot

  glGenBuffers(1, addr result.id)
  glBindBuffer(GL_UNIFORM_BUFFER, result.id)
  var dataRef: ptr T = nil
  if data.isSome:
    result.data = data.get
    dataRef = addr result.data
  glBufferData(GL_UNIFORM_BUFFER, sizeof T, dataRef, storageType)
  glBindBufferBase(GL_UNIFORM_BUFFER, shaderSlot, result.id)

# TODO: Add function for associating the UBO with more shaders (for UBOs that get passed between shaders like compute -> vertex/fragment)

proc glBind[T](storage: ShaderStorageRef[T]) = glBindBuffer(GL_UNIFORM_BUFFER, storage.id)
proc use*[T](storage: ShaderStorageRef[T], shader: ShaderRef) =
  storage.glBind()
  let slot = storage.shaderSlots[shader.id]
  glBindBufferBase(GL_UNIFORM_BUFFER, slot, storage.id)

proc upload*[T](s: ShaderStorageRef[T], storageType: Option[GLenum]) =
  s.glBind()
  let storageType = if storageType.isSome:
    storageType.get
  else:
    s.storageType
  glBufferData(GL_UNIFORM_BUFFER, sizeof T, addr s.data, storageType)

proc uploadRegion*[T](storage: ShaderStorageRef[T], offset: int, size: int) =
  storage.glBind()
  glBufferSubData(GL_UNIFORM_BUFFER, offset, size, addr storage.data)

template uploadField*[T](storage: ShaderStorageRef[T], obj, field, body: untyped) =
  body
  storage.uploadRegion(T.offsetOf(field), sizeof obj.field)

proc cleanup*(s: var ShaderStorageRef) =
  glDeleteBuffers(1, addr s.id)
  s = nil

proc `=dispose`*(s: var ShaderStorageRef) = s.cleanup()

type
  InitBuf*[T: object] = tuple[data: seq[T], bufType: GLenum]
  
  VertexAttrib = tuple[glType: GLenum, count: int, size: int]

  # TODO: Add partial uploads/updates for VBO
  VertexBufferRef*[T: object] = ref object
    id: GLuint
    bufferType: GLenum
    data: seq[T] # Should probably be ref to avoid copying large buffers?
    vertexAttribs: seq[VertexAttrib]
    typeName: string
    slot: int # VBO binding slot

proc glBind*[T: object](b: VertexBufferRef[T]) = glBindBuffer(GL_ARRAY_BUFFER, b.id)
proc upload*[T: object](b: var VertexBufferRef[T], data: seq[T], bufferType: GLenum) =
  b.glBind()
  if data.len > 0:
    b.data = data
    b.bufferType = bufferType
    glBufferData(GL_ARRAY_BUFFER, b.data.len * sizeof T, addr b.data[0], b.bufferType)
  else:
    raise newException(Exception, "Can't upload empty buffer")

# TODO: Add more vector types (ints) and add normalization
proc initVertexBuffer*[T: object](
  initBufOpt: Option[InitBuf[T]] = InitBuf[T].none, treatInvalidTypesAsPadding: bool = false,
  fieldOverrides: Option[Table[string, GLenum]] = Table[string, GLenum].none
): VertexBufferRef[T] =
  result = new VertexBufferRef[T]

  glGenBuffers(1, addr result.id)
  for name, val in fieldPairs(T.default):
    if fieldOverrides.isSome and fieldOverrides.get.hasKey(name):
      result.vertexAttribs.add (fieldOverrides.get[name], 1, val.typeof().sizeof()) # Is the size here correct?
    else:
      let typeName = $typeof(val)
      result.typeName = typeName

      when typeof(val) is GLbyte:
        result.vertexAttribs.add (cGL_BYTE, 1, val.typeof().sizeof())
      elif typeof(val) is GLubyte:
        result.vertexAttribs.add (GL_UNSIGNED_BYTE, 1, val.typeof().sizeof())
      elif typeof(val) is GLshort:
        result.vertexAttribs.add (cGL_SHORT, 1, val.typeof().sizeof())
      elif typeof(val) is GLushort:
        result.vertexAttribs.add (GL_UNSIGNED_SHORT, 1, val.typeof().sizeof())
      elif typeof(val) is GLint:
        result.vertexAttribs.add (cGL_INT, 1, val.typeof().sizeof())
      elif typeof(val) is GLuint:
        result.vertexAttribs.add (GL_UNSIGNED_INT, 1, val.typeof().sizeof())
      elif typeof(val) is GLhalf:
        result.vertexAttribs.add (GL_HALF_FLOAT, 1, val.typeof().sizeof())
      elif typeof(val) is GLfloat:
        result.vertexAttribs.add (cGL_FLOAT, 1, val.typeof().sizeof())
      elif typeof(val) is GLdouble:
        result.vertexAttribs.add (cGL_DOUBLE, 1, val.typeof().sizeof())
      elif typeof(val) is GLfixed:
        result.vertexAttribs.add (cGL_FIXED, 1, val.typeof().sizeof())
      elif typeof(val) is Vec2f:
        result.vertexAttribs &= (cGL_FLOAT, 2, val.typeof().sizeof())
      elif typeof(val) is Vec2d:
        result.vertexAttribs &= (cGL_DOUBLE, 2, val.typeof().sizeof())
      elif typeof(val) is Vec3f:
        result.vertexAttribs &= (cGL_FLOAT, 3, val.typeof().sizeof())
      elif typeof(val) is Vec3d:
        result.vertexAttribs &= (cGL_DOUBLE, 3, val.typeof().sizeof())
      elif typeof(val) is Vec4f:
        result.vertexAttribs &= (cGL_FLOAT, 4, val.typeof().sizeof())
      elif typeof(val) is Vec4d:
        result.vertexAttribs &= (cGL_DOUBLE, 4, val.typeof().sizeof())
      elif treatInvalidTypesAsPadding:
        result.vertexAttribs &= (GL_DONT_CARE, 1, val.typeof().sizeof())
      else:
        raise newException(Exception, fmt"Invalid type for vertex: {typeName}")

  if initBufOpt.isSome:
    let initBuf = initBufOpt.get
    result.upload(initBuf.data, initBuf.bufType)

const GlIntTypes = [ cGL_BYTE, GL_UNSIGNED_BYTE, cGL_SHORT, GL_UNSIGNED_SHORT, cGL_int, GL_UNSIGNED_INT ]
# Not including double here means that splitting CPU-side doubles to floats on the GPU isn't possible.
# There shouldn't be a good use case for it anyway.
const GlFloatTypes = [ GL_HALF_FLOAT, cGL_FLOAT, cGL_FIXED, GL_FLOAT_VEC2, GL_FLOAT_VEC3, GL_FLOAT_VEC4 ] 
const GlDoubleTypes = [ cGL_DOUBLE, GL_DOUBLE_VEC2, GL_DOUBLE_VEC3, GL_DOUBLE_VEC4 ]

proc use*[T](b: VertexBufferRef[T]) =
  b.glBind()

  var offset = 0
  for i, attrib in b.vertexAttribs:
    if attrib.glType == GL_DONT_CARE: # Ignore padding
      offset += attrib.size
      continue
    elif attrib.glType in GlFloatTypes:
      glVertexAttribFormat(i, attrib.count, attrib.glType, false, offset)
    elif attrib.glType in GlIntTypes:
      glVertexAttribIFormat(i, attrib.count, attrib.glType, offset)
    elif attrib.glType in GlDoubleTypes:
      glVertexAttribLFormat(i, attrib.count, attrib.glType, offset)

    glVertexAttribBinding(i, b.slot)
    glEnableVertexAttribArray(i)
    offset += attrib.size

  glBindVertexBuffer(b.slot, b.id, 0, offset)
  glBindBuffer(GL_ARRAY_BUFFER, 0) # VBO can be unbound as its now part of the VAO

proc cleanup*[T](b: var VertexBufferRef[T]) =
  glDeleteBuffers(1, addr b.id)
  b = nil
proc `=dispose`*[T](b: var VertexBufferRef[T]) = b.cleanup()

type
  InitEBuf* = tuple[data: seq[GLuint], bufType: GLenum]
  ElementBufferRef* = ref object
    id: GLuint
    indices: seq[GLuint]

proc glBind*(b: ElementBufferRef) = glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, b.id)

proc upload*(b: var ElementBufferRef, indices: seq[GLuint], bufferType: GLenum) =
  b.glBind()
  b.indices = indices
  glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.len * sizeof GLuint, addr b.indices[0], bufferType)

proc initElementBuffer*(initBufOpt: Option[InitEBuf] = InitEBuf.none): ElementBufferRef = 
  result = new ElementBufferRef
  glGenBuffers(1, addr result.id)

  if initBufOpt.isSome:
    let initBuf = initBufOpt.get
    result.upload(initBuf.data, initBuf.bufType)

proc cleanup*(b: var ElementBufferRef) =
  glDeleteBuffers(1, addr b.id)
  b = nil
proc `=dispose`*(b: var ElementBufferRef) = b.cleanup()

type
  VertexArrayRef* = ref object
    id: GLuint
    attachedElementBuffer: ElementBufferRef

proc initVertexArray*(): VertexArrayRef =
  result = new VertexArrayRef
  glGenVertexArrays(1, addr result.id)

proc cleanup*(a: var VertexArrayRef) =
  glDeleteVertexArrays(1, addr a.id)
  a = nil
proc `=dispose`*(a: var VertexArrayRef) = a.cleanup()

proc isActive*(a: VertexArrayRef): bool =
  var currentVertexArrayIdStore: GLint
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, addr currentVertexArrayIdStore)
  return a.id == cast[GLuint](currentVertexArrayIdStore)

proc attachElementBuffer*(a: var VertexArrayRef, b: ElementBufferRef) =
  a.attachedElementBuffer = b
  if a.isActive():
    b.glBind()

proc glBind(a: VertexArrayRef) = glBindVertexArray(a.id)
proc use*(a: VertexArrayRef) =
  a.glBind()
  if a.attachedElementBuffer != nil:
    a.attachedElementBuffer.glBind()

# TODO: Add error handling from https://learnopengl.com/In-Practice/Debugging
