import std/[strformat, options, lenientops]
import pkg/[glm]
import ./glad/gl
import GlUtils 

type
  SdfInstructionKind* {.size: sizeof(uint8).} = enum
    # Operations
    AddOp, SubOp, InterOp, XorOp, SmoothAddOp, SmoothSubOp, SmoothInterOp, 
    # Shapes
    Sphere, Box, RoundBox, BoxFrame, Cone, CappedCone, HexPrism, TriPrism, Capsule,
    CappedCylinder, RoundedCylinder, CutSphere, Octahedron, Pyramid, Triangle, Quad
  Material* = object
    color: Vec3f
    metalness: GLfloat
  # A distinct type could be used to give extra type safety for material, argument and runtime data indices. Its a bit annoying though,
  # because there is no easy way to borrow all operators for a distinct type.
  # ArgIndex* = distinct uint32

makeGlObjects(AlignToSize, dontAlignByType):
  type
    SdfProgramData* = object
      materialData*: array[256, Material]
      args*: seq[uint32]
    SdfInstruction* = object
      kind*: SdfInstructionKind
      runtimeArgsI*: uint8
      argsI*: uint16
      outputI*: uint8
      materialI*: uint8
      argCount*: uint8

proc emptySdfProgram*(): seq[SdfInstruction] = @[]

const maxOutputSlots = 10

# TODO: Keep track of which output slots have been used with a combining operation and raise an exception when making
# a new instruction that would overwrite the unused result. Also add a better API for dynamically changing existing shapes
# and instructions (low priority).
type
  SceneBuilder* = object
    nextArgI: uint16 = 0
    nextOutputI: uint8 = 0
    data: ref SdfProgramData
    instructions: ref seq[SdfInstruction]

proc initSceneBuilder*(data: ref SdfProgramData, instructions: ref seq[SdfInstruction]): SceneBuilder =
  SceneBuilder(data: data, instructions: instructions)

proc makeInsn(
  kind: SdfInstructionKind; argsI: uint16; outputI, argCount: uint8; runtimeArgsI = uint8.none
): SdfInstruction =
  result = SdfInstruction(kind: kind, argsI: argsI, outputI: outputI, argCount: argCount)
  if runtimeArgsI.isSome: result.runtimeArgsI = runtimeArgsI.get

template makeUintArgs(arr: untyped) =
  const arrSize = sizeof(arr[0]) div sizeof(uint32) * arr.len
  let args {.inject.} = cast[array[arr.len, uint32]](arr)

proc addArgs(prog: var SceneBuilder, args: openArray[uint32]) =
  prog.data.args &= args
  prog.nextArgI += args.len.uint16

# This is broken but why?
proc size(params: openArray[uint32]): uint32 = sizeof(params) div 4 # How many uint32s is this params array?
proc addInsnWithOutput(prog: var SceneBuilder, i: SdfInstruction): tuple[outputI: uint8, instI: int] =
  result = (prog.nextOutputI, prog.instructions[].len)
  prog.instructions[].add i
  echo i
  prog.nextOutputI += 1
  prog.nextOutputI = prog.nextOutputI mod maxOutputSlots

const defaultRoundingFactor: GLfloat = 0.5

# These functions return the output parameter slot where their results will be written
# TODO: Generate from function signature using macros?
proc addSphere*(prog: var SceneBuilder; p: Vec3f, r: GLfloat): tuple[outputI: uint8, instI: int] =
  makeUintArgs [p.x, p.y, p.z, r]
  result = prog.addInsnWithOutput makeInsn(Sphere, prog.nextArgI, prog.nextOutputI, sizeof(args) div 4)
  prog.addArgs args
proc addBox*(prog: var SceneBuilder; p: Vec3f, halfExtents: Vec3f): tuple[outputI: uint8, instI: int] =
  makeUintArgs [p.x, p.y, p.z, halfExtents.x, halfExtents.y, halfExtents.z]
  result = prog.addInsnWithOutput makeInsn(Box, prog.nextArgI, prog.nextOutputI, sizeof(args) div 4)
  prog.addArgs args
proc addRoundBox*(prog: var SceneBuilder; p: Vec3f, halfExtents: Vec3f, r = defaultRoundingFactor): tuple[outputI: uint8, instI: int] =
  makeUintArgs [p.x, p.y, p.z, halfExtents.x, halfExtents.y, halfExtents.z, r]
  result = prog.addInsnWithOutput makeInsn(RoundBox, prog.nextArgI, prog.nextOutputI, sizeof(args) div 4)
  prog.addArgs args
proc addBoxFrame*(prog: var SceneBuilder; p: Vec3f, halfExtents: Vec3f, e: GLfloat): tuple[outputI: uint8, instI: int] =
  makeUintArgs [p.x, p.y, p.z, halfExtents.x, halfExtents.y, halfExtents.z, e]
  result = prog.addInsnWithOutput makeInsn(BoxFrame, prog.nextArgI, prog.nextOutputI, sizeof(args) div 4)
  prog.addArgs args
proc addCone*(prog: var SceneBuilder; p: Vec3f, c: Vec2f, h: GLfloat): tuple[outputI: uint8, instI: int] =
  makeUintArgs [p.x, p.y, p.z, c.x, c.y, h]
  result = prog.addInsnWithOutput makeInsn(Cone, prog.nextArgI, prog.nextOutputI, sizeof(args) div 4)
  prog.addArgs args
proc addCappedCone*(prog: var SceneBuilder; p, a, b: Vec3f; ra, rb: GLfloat): tuple[outputI: uint8, instI: int] =
  makeUintArgs [p.x, p.y, p.z, a.x, a.y, a.z, b.x, b.y, b.z, ra, rb]
  result = prog.addInsnWithOutput makeInsn(CappedCone, prog.nextArgI, prog.nextOutputI, sizeof(args) div 4)
  prog.addArgs args
proc addHexPrism*(prog: var SceneBuilder; p: Vec3f, h: Vec2f): tuple[outputI: uint8, instI: int] =
  makeUintArgs [p.x, p.y, p.z, h.x, h.y]
  result = prog.addInsnWithOutput makeInsn(HexPrism, prog.nextArgI, prog.nextOutputI, sizeof(args) div 4)
  prog.addArgs args
proc addTriPrism*(prog: var SceneBuilder; p: Vec3f, h: Vec2f): tuple[outputI: uint8, instI: int] =
  makeUintArgs [p.x, p.y, p.z, h.x, h.y]
  result = prog.addInsnWithOutput makeInsn(TriPrism, prog.nextArgI, prog.nextOutputI, sizeof(args) div 4)
  prog.addArgs args
proc addCapsule*(prog: var SceneBuilder; p: Vec3f; h, r: GLfloat): tuple[outputI: uint8, instI: int] =
  makeUintArgs [p.x, p.y, p.z, h, r]
  result = prog.addInsnWithOutput makeInsn(Capsule, prog.nextArgI, prog.nextOutputI, sizeof(args) div 4)
  prog.addArgs args
proc addCappedCylinder*(prog: var SceneBuilder; p, a, b: Vec3f; r: GLfloat): tuple[outputI: uint8, instI: int] =
  makeUintArgs [p.x, p.y, p.z, a.x, a.y, a.z, b.x, b.y, b.z, r]
  result = prog.addInsnWithOutput makeInsn(CappedCylinder, prog.nextArgI, prog.nextOutputI, sizeof(args) div 4)
  prog.addArgs args
proc addRoundedCylinder*(prog: var SceneBuilder; p: Vec3f; ra, rb: GLfloat; h = defaultRoundingFactor): tuple[outputI: uint8, instI: int] =
  makeUintArgs [p.x, p.y, p.z, ra, rb, h]
  result = prog.addInsnWithOutput makeInsn(RoundedCylinder, prog.nextArgI, prog.nextOutputI, sizeof(args) div 4)
  prog.addArgs args
proc addCutSphere*(prog: var SceneBuilder; p: Vec3f; r, h: GLfloat): tuple[outputI: uint8, instI: int] =
  makeUintArgs [p.x, p.y, p.z, r, h]
  result = prog.addInsnWithOutput makeInsn(CutSphere, prog.nextArgI, prog.nextOutputI, sizeof(args) div 4)
  prog.addArgs args
proc addOctahedron*(prog: var SceneBuilder; p: Vec3f, s: GLfloat): tuple[outputI: uint8, instI: int] =
  makeUintArgs [p.x, p.y, p.z, s]
  result = prog.addInsnWithOutput makeInsn(Octahedron, prog.nextArgI, prog.nextOutputI, sizeof(args) div 4)
  prog.addArgs args
proc addPyramid*(prog: var SceneBuilder; p: Vec3f, h: GLfloat): tuple[outputI: uint8, instI: int] =
  makeUintArgs [p.x, p.y, p.z, h]
  result = prog.addInsnWithOutput makeInsn(Pyramid, prog.nextArgI, prog.nextOutputI, sizeof(args) div 4)
  prog.addArgs args
proc addTriangle*(prog: var SceneBuilder; p, a, b, c: Vec3f): tuple[outputI: uint8, instI: int] =
  makeUintArgs [p.x, p.y, p.z, a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z]
  result = prog.addInsnWithOutput makeInsn(Triangle, prog.nextArgI, prog.nextOutputI, sizeof(args) div 4)
  prog.addArgs args
proc addQuad*(prog: var SceneBuilder; p, a, b, c, d: Vec3f): tuple[outputI: uint8, instI: int] =
  makeUintArgs [p.x, p.y, p.z, a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, d.x, d.y, d.z]
  result = prog.addInsnWithOutput makeInsn(Quad, prog.nextArgI, prog.nextOutputI, sizeof(args) div 4)
  prog.addArgs args

proc assertContiguousInputs(inputs: openArray[uint8]) =
  when not defined(release) and not defined(danger):
    for i in 0 ..< inputs.high:
      assert(inputs[i + 1] - inputs[i] == 1.uint8, "Inputs for SDF must be next to each other in memory. " &
             "The GPU SDF instruction interpreter can only read parameters in order.")
proc combine*(prog: var SceneBuilder; d1Index, d2Index: uint8): tuple[outputI: uint8, instI: int] =
  assertContiguousInputs [d1Index, d2Index]
  result = prog.addInsnWithOutput makeInsn(AddOp, uint8.high, prog.nextOutputI, 2, d1Index.some)
proc cut*(prog: var SceneBuilder; d1Index, d2Index: uint8): tuple[outputI: uint8, instI: int] =
  assertContiguousInputs [d1Index, d2Index]
  result = prog.addInsnWithOutput makeInsn(SubOp, uint8.high, prog.nextOutputI, 2, d1Index.some)
proc intersect*(prog: var SceneBuilder; d1Index, d2Index: uint8): tuple[outputI: uint8, instI: int] =
  assertContiguousInputs [d1Index, d2Index]
  result = prog.addInsnWithOutput makeInsn(InterOp, uint8.high, prog.nextOutputI, 2, d1Index.some)
proc combineWithoutOverlap*(prog: var SceneBuilder; d1Index, d2Index: uint8): tuple[outputI: uint8, instI: int] =
  assertContiguousInputs [d1Index, d2Index]
  result = prog.addInsnWithOutput makeInsn(XorOp, uint8.high, prog.nextOutputI, 2, d1Index.some)
proc smoothlyCombine*(prog: var SceneBuilder; d1Index, d2Index: uint8; k = defaultRoundingFactor): tuple[outputI: uint8, instI: int] =
  makeUintArgs [k]
  assertContiguousInputs [d1Index, d2Index]
  result = prog.addInsnWithOutput makeInsn(SmoothAddOp, prog.nextArgI, prog.nextOutputI, 2, d1Index.some)
  prog.addArgs args
proc smoothlyCut*(prog: var SceneBuilder; d1Index, d2Index: uint8; k = defaultRoundingFactor): tuple[outputI: uint8, instI: int] =
  makeUintArgs [k]
  assertContiguousInputs [d1Index, d2Index]
  result = prog.addInsnWithOutput makeInsn(SmoothSubOp, prog.nextArgI, prog.nextOutputI, 2, d1Index.some)
  prog.addArgs args
proc smoothlyIntersect*(prog: var SceneBuilder; d1Index, d2Index: uint8; k = defaultRoundingFactor): tuple[outputI: uint8, instI: int] =
  makeUintArgs [k]
  assertContiguousInputs [d1Index, d2Index]
  result = prog.addInsnWithOutput makeInsn(SmoothInterOp, prog.nextArgI, prog.nextOutputI, 2, d1Index.some)
  prog.addArgs args
