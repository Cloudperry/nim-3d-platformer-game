import std/[strformat, options, lenientops]
import pkg/[glm]
import ./glad/gl
import GlUtils 

#[enum SdfInstructionKind {
	// Operations
	AddOp, SubOp, InterOp, XorOp, SmoothAddOp, SmoothSubOp, SmoothInterOp, 
	// Shapes
	Sphere, Box, RoundBox, BoxFrame, Cone, CappedCone, HexPrism, TriPrism, Capsule,
	CappedCylinder, RoundedCylinder, CutSphere, Octahedron, Pyramid, Triangle, Quad
}

struct Material {
	float3 color; // Add alpha channel for transparency and add refractive index?
	float metalness; // How reflective is the surface? Controls how much of diffuse/specular lighting the surface will have.
}

struct SdfProgramData {
	 Material materialData[256];
	 // This is enough for about 8000 shapes in the worst case, but it should be enough for most SDF scenes that can run in real-time
	 uint params[65536]; 
	 // Index to params where instruction outputs start. For implementing safety mechanisms together with isLeafNode.
	 // uint16_t instructionOutputsStart;
}

struct SdfInstruction {
	SdfInstructionKind kind;
	uint16_t argsIndex; // Index to array that has both the outputs of this SDF program and the input parameters
	uint16_t outputIndex; // Index to the program outputs array where this instruction will put its return value to
	uint8_t materialIndex; // Zero for SDF nodes that aren't a shape
	uint8_t paramsSize; // How many bytes starting from argsIndex are parameters for this instruction?
	uint8_t _pad[6];
	// This could be used to implement a safety mechanism that clearly shows if a non-leaf node is trying to read program input parameters.
	// Non-leaf nodes should only read results of previous instructions.
	// bool isLeafNode; 
}]#

type
  SdfInstructionKind* = enum
    # Operations
    AddOp, SubOp, InterOp, XorOp, SmoothAddOp, SmoothSubOp, SmoothInterOp, 
    # Shapes
    Sphere, Box, RoundBox, BoxFrame, Cone, CappedCone, HexPrism, TriPrism, Capsule,
    CappedCylinder, RoundedCylinder, CutSphere, Octahedron, Pyramid, Triangle, Quad
  Material* = object
    color: Vec3f
    metalness: GLfloat
  ParamIndex* = distinct uint32
  MaterialIndex* = distinct uint32

proc `+`*(p: ParamIndex, offset: int): ParamIndex = ParamIndex(p.uint32 + offset.uint32)
proc `+=`*(p: var ParamIndex, offset: int) =
  p = ParamIndex(p.uint16 + offset.uint32)
proc `div`*(p: ParamIndex, n: int): ParamIndex = ParamIndex(p.uint32 div n.uint32)
proc `mod`*(p: ParamIndex, n: int): ParamIndex = ParamIndex(p.uint32 mod n.uint32)
proc `-`*(p1, p2: ParamIndex): ParamIndex {.borrow.}
proc `<`*(p1, p2: ParamIndex): bool {.borrow.}
proc `==`*(p1, p2: ParamIndex): bool {.borrow.}
proc `$`*(p: ParamIndex): string {.borrow.}
proc `$`*(p: MaterialIndex): string {.borrow.}

#[
uint packedData0;
	// First 8 bits kind: Packed instruction kind enum
	// Next 8 bits runtimeArgsIndex: Index to the temporary runtime outputs array
	// Last 16 bits argsIndex: Index to array that has the input parameters for this SDF program
	
	uint packedData1;
	// First 8 bits outputIndex: Index to the runtime outputs array where this instruction will put its return value to
	// Next 8 bits materialIndex: Index to the materialData array
	// Next 8 bits paramsSize: How many bytes starting from argsIndex are parameters for this instruction (for debug purposes)
]#

makeGlObjects(AlignToSize, dontAlignByType):
  type
    SdfProgramData* = object
      materialData*: array[256, Material]
      params*: seq[uint32]
    SdfInstruction* = object
      kind*: SdfInstructionKind
      runtimeArgsIndex*: uint8
      argsIndex*: uint16
      outputIndex*: uint8
      materialIndex*: uint8
      paramsSize*: uint8

proc emptySdfProgram*(): seq[SdfInstruction] = @[]

const outputsStartI = uint16.high div 2

# TODO: Keep track of which output slots have been used with a combining operation and raise an exception when making
# a new instruction that would overwrite the unused result. Also add a better API for dynamically changing existing shapes
# and instructions (low priority).
type
  SceneBuilder* = object
    nextParamI: uint16 = 0
    nextOutputI: uint8 = 0
    data: ref SdfProgramData
    instructions: ref seq[SdfInstruction]

proc initSceneBuilder*(data: ref SdfProgramData, instructions: ref seq[SdfInstruction]): SceneBuilder =
  SceneBuilder(data: data, instructions: instructions)

proc makeInsn(
  kind: SdfInstructionKind; argsIndex: uint16; outputIndex, paramsSize: uint8; runtimeArgsIndex = uint8.none
): SdfInstruction =
  result = SdfInstruction(kind: kind, argsIndex: argsIndex, outputIndex: outputIndex, paramsSize: paramsSize)
  if runtimeArgsIndex.isSome: result.runtimeArgsIndex = runtimeArgsIndex.get

template makeUintParams(arr: untyped) =
  const arrSize = sizeof(arr[0]) div sizeof(uint32) * arr.len
  let params {.inject.} = cast[array[arr.len, uint32]](arr)

proc addParams(prog: var SceneBuilder, params: openArray[uint32]) =
  prog.data.params &= params
  prog.nextParamI += params.len.uint16
  assert(prog.nextParamI < outputsStartI, "SDF program input parameters overflowed to the output parameters' area")

# This is broken but why?
proc size(params: openArray[uint32]): uint32 = sizeof(params) div 4 # How many uint32s is this params array?
proc addInsnWithOutput(prog: var SceneBuilder, i: SdfInstruction): tuple[outputI: uint8, instI: int] =
  result = (prog.nextOutputI, prog.instructions[].len)
  prog.instructions[].add i
  echo i
  prog.nextOutputI += 1
  prog.nextOutputI = prog.nextOutputI mod 30

const defaultRoundingFactor: GLfloat = 0.5

# These functions return the output parameter slot where their results will be written
# TODO: Generate from function signature using macros?
proc addSphere*(prog: var SceneBuilder; p: Vec3f, r: GLfloat): tuple[outputI: uint8, instI: int] =
  makeUintParams [p.x, p.y, p.z, r]
  result = prog.addInsnWithOutput makeInsn(Sphere, prog.nextParamI, prog.nextOutputI, sizeof(params) div 4)
  prog.addParams params
proc addBox*(prog: var SceneBuilder; p: Vec3f, halfExtents: Vec3f): tuple[outputI: uint8, instI: int] =
  makeUintParams [p.x, p.y, p.z, halfExtents.x, halfExtents.y, halfExtents.z]
  result = prog.addInsnWithOutput makeInsn(Box, prog.nextParamI, prog.nextOutputI, sizeof(params) div 4)
  prog.addParams params
proc addRoundBox*(prog: var SceneBuilder; p: Vec3f, halfExtents: Vec3f, r = defaultRoundingFactor): tuple[outputI: uint8, instI: int] =
  makeUintParams [p.x, p.y, p.z, halfExtents.x, halfExtents.y, halfExtents.z, r]
  result = prog.addInsnWithOutput makeInsn(RoundBox, prog.nextParamI, prog.nextOutputI, sizeof(params) div 4)
  prog.addParams params
proc addBoxFrame*(prog: var SceneBuilder; p: Vec3f, halfExtents: Vec3f, e: GLfloat): tuple[outputI: uint8, instI: int] =
  makeUintParams [p.x, p.y, p.z, halfExtents.x, halfExtents.y, halfExtents.z, e]
  result = prog.addInsnWithOutput makeInsn(BoxFrame, prog.nextParamI, prog.nextOutputI, sizeof(params) div 4)
  prog.addParams params
proc addCone*(prog: var SceneBuilder; p: Vec3f, c: Vec2f, h: GLfloat): tuple[outputI: uint8, instI: int] =
  makeUintParams [p.x, p.y, p.z, c.x, c.y, h]
  result = prog.addInsnWithOutput makeInsn(Cone, prog.nextParamI, prog.nextOutputI, sizeof(params) div 4)
  prog.addParams params
proc addCappedCone*(prog: var SceneBuilder; p, a, b: Vec3f; ra, rb: GLfloat): tuple[outputI: uint8, instI: int] =
  makeUintParams [p.x, p.y, p.z, a.x, a.y, a.z, b.x, b.y, b.z, ra, rb]
  result = prog.addInsnWithOutput makeInsn(CappedCone, prog.nextParamI, prog.nextOutputI, sizeof(params) div 4)
  prog.addParams params
proc addHexPrism*(prog: var SceneBuilder; p: Vec3f, h: Vec2f): tuple[outputI: uint8, instI: int] =
  makeUintParams [p.x, p.y, p.z, h.x, h.y]
  result = prog.addInsnWithOutput makeInsn(HexPrism, prog.nextParamI, prog.nextOutputI, sizeof(params) div 4)
  prog.addParams params
proc addTriPrism*(prog: var SceneBuilder; p: Vec3f, h: Vec2f): tuple[outputI: uint8, instI: int] =
  makeUintParams [p.x, p.y, p.z, h.x, h.y]
  result = prog.addInsnWithOutput makeInsn(TriPrism, prog.nextParamI, prog.nextOutputI, sizeof(params) div 4)
  prog.addParams params
proc addCapsule*(prog: var SceneBuilder; p: Vec3f; h, r: GLfloat): tuple[outputI: uint8, instI: int] =
  makeUintParams [p.x, p.y, p.z, h, r]
  result = prog.addInsnWithOutput makeInsn(Capsule, prog.nextParamI, prog.nextOutputI, sizeof(params) div 4)
  prog.addParams params
proc addCappedCylinder*(prog: var SceneBuilder; p, a, b: Vec3f; r: GLfloat): tuple[outputI: uint8, instI: int] =
  makeUintParams [p.x, p.y, p.z, a.x, a.y, a.z, b.x, b.y, b.z, r]
  result = prog.addInsnWithOutput makeInsn(CappedCylinder, prog.nextParamI, prog.nextOutputI, sizeof(params) div 4)
  prog.addParams params
proc addRoundedCylinder*(prog: var SceneBuilder; p: Vec3f; ra, rb: GLfloat; h = defaultRoundingFactor): tuple[outputI: uint8, instI: int] =
  makeUintParams [p.x, p.y, p.z, ra, rb, h]
  result = prog.addInsnWithOutput makeInsn(RoundedCylinder, prog.nextParamI, prog.nextOutputI, sizeof(params) div 4)
  prog.addParams params
proc addCutSphere*(prog: var SceneBuilder; p: Vec3f; r, h: GLfloat): tuple[outputI: uint8, instI: int] =
  makeUintParams [p.x, p.y, p.z, r, h]
  result = prog.addInsnWithOutput makeInsn(CutSphere, prog.nextParamI, prog.nextOutputI, sizeof(params) div 4)
  prog.addParams params
proc addOctahedron*(prog: var SceneBuilder; p: Vec3f, s: GLfloat): tuple[outputI: uint8, instI: int] =
  makeUintParams [p.x, p.y, p.z, s]
  result = prog.addInsnWithOutput makeInsn(Octahedron, prog.nextParamI, prog.nextOutputI, sizeof(params) div 4)
  prog.addParams params
proc addPyramid*(prog: var SceneBuilder; p: Vec3f, h: GLfloat): tuple[outputI: uint8, instI: int] =
  makeUintParams [p.x, p.y, p.z, h]
  result = prog.addInsnWithOutput makeInsn(Pyramid, prog.nextParamI, prog.nextOutputI, sizeof(params) div 4)
  prog.addParams params
proc addTriangle*(prog: var SceneBuilder; p, a, b, c: Vec3f): tuple[outputI: uint8, instI: int] =
  makeUintParams [p.x, p.y, p.z, a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z]
  result = prog.addInsnWithOutput makeInsn(Triangle, prog.nextParamI, prog.nextOutputI, sizeof(params) div 4)
  prog.addParams params
proc addQuad*(prog: var SceneBuilder; p, a, b, c, d: Vec3f): tuple[outputI: uint8, instI: int] =
  makeUintParams [p.x, p.y, p.z, a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, d.x, d.y, d.z]
  result = prog.addInsnWithOutput makeInsn(Quad, prog.nextParamI, prog.nextOutputI, sizeof(params) div 4)
  prog.addParams params

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
  makeUintParams [k]
  assertContiguousInputs [d1Index, d2Index]
  result = prog.addInsnWithOutput makeInsn(SmoothAddOp, prog.nextParamI, prog.nextOutputI, 2, d1Index.some)
  prog.addParams params
proc smoothlyCut*(prog: var SceneBuilder; d1Index, d2Index: uint8; k = defaultRoundingFactor): tuple[outputI: uint8, instI: int] =
  makeUintParams [k]
  assertContiguousInputs [d1Index, d2Index]
  result = prog.addInsnWithOutput makeInsn(SmoothSubOp, prog.nextParamI, prog.nextOutputI, 2, d1Index.some)
  prog.addParams params
proc smoothlyIntersect*(prog: var SceneBuilder; d1Index, d2Index: uint8; k = defaultRoundingFactor): tuple[outputI: uint8, instI: int] =
  makeUintParams [k]
  assertContiguousInputs [d1Index, d2Index]
  result = prog.addInsnWithOutput makeInsn(SmoothInterOp, prog.nextParamI, prog.nextOutputI, 2, d1Index.some)
  prog.addParams params
