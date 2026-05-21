import std/[sugar, lenientops]
import glad/gl
import pkg/glm
import Scene, GlUtils

type SimpleModel* = tuple[vertices: seq[ColoredVertex], indices: seq[GLuint]]

proc makeBox*(halfExtents: Vec3f, color: Vec3f): SimpleModel =
  let topRightFront = halfExtents * vec3f(1.0, 1.0, 1.0)
  let topLeftFront = halfExtents * vec3f(-1.0, 1.0, 1.0)
  let botLeftFront = halfExtents * vec3f(-1.0, -1.0, 1.0)
  let botRightFront = halfExtents * vec3f(1.0, -1.0, 1.0)
  let topRightBack = halfExtents * vec3f(1.0, 1.0, -1.0)
  let topLeftBack = halfExtents * vec3f(-1.0, 1.0, -1.0)
  let botLeftBack = halfExtents * vec3f(-1.0, -1.0, -1.0)
  let botRightBack = halfExtents * vec3f(1.0, -1.0, -1.0)
  var vertices: seq[ColoredVertex]
  # Front
  for vert in [botLeftFront, botRightFront, topRightFront, topLeftFront]:
    vertices.add ColoredVertex(pos: vert, color: color, normal: vec3f(0, 0, 1))
  # Back
  for vert in [botRightBack, botLeftBack, topLeftBack, topRightBack]:
    vertices.add ColoredVertex(pos: vert, color: color, normal: vec3f(0, 0, -1))
  # Right
  for vert in [botRightFront, botRightBack, topRightBack, topRightFront]:
    vertices.add ColoredVertex(pos: vert, color: color, normal: vec3f(1, 0, 0))
  # Left
  for vert in [botLeftBack, botLeftFront, topLeftFront, topLeftBack]:
    vertices.add ColoredVertex(pos: vert, color: color, normal: vec3f(-1, 0, 0))
  # Up
  for vert in [topLeftFront, topRightFront, topRightBack, topLeftBack]:
    vertices.add ColoredVertex(pos: vert, color: color, normal: vec3f(0, 1, 0))
  # Down
  for vert in [botRightFront, botLeftFront, botLeftBack, botRightBack]:
    vertices.add ColoredVertex(pos: vert, color: color, normal: vec3f(0, -1, 0))
  
  var indices: seq[int]
  for base in countup(0, 23, 4):
    indices.add base
    indices.add base + 1
    indices.add base + 2
    indices.add base
    indices.add base + 2
    indices.add base + 3

  return (vertices: vertices, indices: indices)

proc makePyramid*(halfSizeLen: float32, color: Vec3f): SimpleModel =
  let apex = vec3f(0, halfSizeLen, 0)
  let botLeftFront  = vec3f(-halfSizeLen, -halfSizeLen,  halfSizeLen)
  let botRightFront = vec3f( halfSizeLen, -halfSizeLen,  halfSizeLen)
  let botRightBack  = vec3f( halfSizeLen, -halfSizeLen, -halfSizeLen)
  let botLeftBack   = vec3f(-halfSizeLen, -halfSizeLen, -halfSizeLen)

  var vertices: seq[ColoredVertex]
  # Base
  for vert in [botRightFront, botLeftFront, botLeftBack, botRightBack]:
    vertices.add ColoredVertex(pos: vert, color: color, normal: vec3f(0, -1, 0))
  # Front
  for vert in [apex, botLeftFront, botRightFront]:
    vertices.add ColoredVertex(pos: vert, color: color, normal: normalize(vec3f(0, 0.5, 0.5)))
  # Back
  for vert in [apex, botRightBack, botLeftBack]:
    vertices.add ColoredVertex(pos: vert, color: color, normal: normalize(vec3f(0, 0.5, -0.5)))
  # Right
  for vert in [apex, botRightFront, botRightBack]:
    vertices.add ColoredVertex(pos: vert, color: color, normal: normalize(vec3f(0.5, 0.5, 0)))
  # Left
  for vert in [apex, botLeftBack, botLeftFront]:
    vertices.add ColoredVertex(pos: vert, color: color, normal: normalize(vec3f(-0.5, 0.5, 0)))

  var indices: seq[int]
  # Base quad
  indices.add [0, 1, 2, 0, 2, 3]
  # Four triangle sides
  for base in countup(4, 15, 3):
    indices.add [base, base + 1, base + 2]

  return (vertices: vertices, indices: indices)

proc makeSphere*(radius: float; slices, stacks: int; color: Vec3f): SimpleModel =
  var vertices: seq[ColoredVertex]
  var indices: seq[int]

  for stack in 0..stacks:
    let phi = PI * float32(stack) / float32(stacks)         # 0..π
    let y = cos(phi)
    let r = sin(phi)
    for slice in 0..slices:
      let theta = 2.0f32 * PI * float32(slice) / float32(slices) # 0..2π
      let x = r * cos(theta)
      let z = r * sin(theta)

      let pos = vec3f(x * radius, y * radius, z * radius)
      let normal = normalize(vec3f(x, y, z))    # outward normal
      vertices.add(ColoredVertex(pos: pos, color: color, normal: normal))

  for stack in 0 ..< stacks:
    for slice in 0 ..< slices:
      let first  = stack * (slices + 1) + slice
      let second = first + slices + 1

      indices.add(first)
      indices.add(first + 1)
      indices.add(second)

      indices.add(second)
      indices.add(first + 1)
      indices.add(second + 1)

  return (vertices, indices)
