import Sdf;
import Lighting;
import SdfTestScenes;

struct SceneUniforms {
	// TODO: Move hitColor and specularExponent to material properties. For now they are scene-global.
	// TODO: Add point lights
  float aspect;
  float3 camPos, camForward, camRight, camUp, hitColor, bgColor;
  float fov;
	float3 mainLightDirection, mainLightColor, ambientLightColor;
	float specularExponent;
}

// TODO: Add union of N shapes and intersection of N shapes to be more efficient with output slots. These could possibly
// even replace the normal binary op versions. This method is possible to use with basically all commutative SDF ops.
enum SdfInstructionKind {
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

#define READ_FLOAT(data, idx) asfloat((data)[idx])

#define READ_FLOAT2(data, idx) float2( \
    asfloat((data)[idx]),         \
    asfloat((data)[(idx)+1])      \
)

#define READ_FLOAT3(data, idx) float3( \
    asfloat((data)[idx]),         \
    asfloat((data)[(idx)+1]),     \
    asfloat((data)[(idx)+2])      \
)

#define WRITE_FLOAT(data, idx, val) \
    (data)[(idx)] = asuint((val))

#define WRITE_FLOAT2(data, idx, val) \
    (data)[(idx)]     = asuint((val).x); \
    (data)[(idx) + 1] = asuint((val).y)

#define WRITE_FLOAT3(data, idx, val) \
    (data)[(idx)]     = asuint((val).x); \
    (data)[(idx) + 1] = asuint((val).y); \
    (data)[(idx) + 2] = asuint((val).z)

// TODO: Add a special SDF program type for emissive shapes. In this program there are only shape instructions and the distances
// are not saved to output slots. Instead the shapes are evaluated one by one and their light contributions are summed up to
// a final light. This avoids the slowness of traversing the whole scene SDF program just to get the light contribution from
// emissives. One problem to solve with this approach is how to get the emissive surface to be correctly lit, since its physical
// geometric shape is now separate from the emission evaluation.

struct SdfProgramData {
	Material materialData[256];
	// If this shader is ever used for a Windows game, this runtime-sized array needs to be replaced. AMD OpenGL drivers fail
	// to link the shader if a dynamic array is used in an SSBO. Zink and GLonD3D12 work, but are unusably slow.
	uint args[];
}

// For complex CSG trees, this can be increased to at least 20 or 30 without destroying performance.
struct SdfProgramRuntimeData {
	uint outputs[10];
}

[ForceInline]
uint getPackedValue(uint packed, uint start, uint length) {
	uint mask = (1u << length) - 1u;
	return (packed >> start) & mask;
}

struct SdfInstruction {
	uint packedData0;
	// First 8 bits kind: Packed instruction kind enum
	// Next 8 bits runtimeArgsIndex: Index to the temporary runtime outputs array
	// Last 16 bits argsIndex: Index to array that has the input parameters for this SDF program
	
	uint packedData1;
	// First 8 bits outputIndex: Index to the runtime outputs array where this instruction will put its return value to
	// Next 8 bits materialIndex: Index to the materialData array
  
  // TODO: Use runtimeArgCount for operations on N shapes at once?
	// Next 8 bits argCount (unused): How many uints starting from argsIndex are parameters for this instruction
	// Last 8 bits runtimeArgCount (unused)

	SdfInstructionKind kind() { return (SdfInstructionKind) getPackedValue(packedData0, 0, 8); }
	uint runtimeArgsI() { return getPackedValue(packedData0, 8, 8); }
	uint argsI() { return getPackedValue(packedData0, 16, 16); }
	uint outputI() { return getPackedValue(packedData1, 0, 8); }
	uint materialI() { return getPackedValue(packedData1, 8, 8); }
	uint argCount() { return getPackedValue(packedData1, 16, 8); }
	uint runtimeArgCount() { return getPackedValue(packedData1, 24, 8); }
}

enum RenderMode {
	BasicLitScene, ShadowedLitScene, UnlitScene, DebugNormals, DebugStepCounts
}

struct DebugSettings {
	RenderMode mode;
}

[[vk::binding(0)]]
ConstantBuffer<SceneUniforms> scene;
[[vk::binding(1)]]
ConstantBuffer<DebugSettings> debugOpt;

[[vk::binding(0)]]
StructuredBuffer<SdfProgramData> sdfProgData;
[[vk::binding(1)]]
StructuredBuffer<SdfInstruction> sdfProg;
[[vk::binding(2)]]
StructuredBuffer<PointLight> pointLights;

struct VertexInput {
  [[vk::location(0)]]
  float2 pos;
  [[vk::location(1)]]
  float2 uv;
}

struct VertexOutput {
  float4 pos : SV_Position;
  float2 fragUv;
}

struct FragmentOutput {
  float4 color : SV_Target0;
}

[shader("vertex")]
VertexOutput vertexMain(VertexInput input) {
  VertexOutput output;
  output.pos = float4(input.pos, 0.0, 1.0);
  output.fragUv = input.uv;
  return output;
}

// Operations eval
[ForceInline]
float evalAddOp(SdfInstruction insn, SdfProgramRuntimeData runtimeData) {
	float d1; float d2;
	d1 = READ_FLOAT(runtimeData.outputs, insn.runtimeArgsI());
	d2 = READ_FLOAT(runtimeData.outputs, insn.runtimeArgsI() + 1);
	return opUnion(d1, d2);
}
[ForceInline]
float evalSubOp(SdfInstruction insn, SdfProgramRuntimeData runtimeData) {
	float d1; float d2;
	d1 = READ_FLOAT(runtimeData.outputs, insn.runtimeArgsI());
	d2 = READ_FLOAT(runtimeData.outputs, insn.runtimeArgsI() + 1);
	return opSubtraction(d1, d2);
}
[ForceInline]
float evalInterOp(SdfInstruction insn, SdfProgramRuntimeData runtimeData) {
	float d1; float d2;
	d1 = READ_FLOAT(runtimeData.outputs, insn.runtimeArgsI());
	d2 = READ_FLOAT(runtimeData.outputs, insn.runtimeArgsI() + 1);
	return opIntersection(d1, d2);
}
[ForceInline]
float evalXorOp(SdfInstruction insn, SdfProgramRuntimeData runtimeData) {
	float d1; float d2;
	d1 = READ_FLOAT(runtimeData.outputs, insn.runtimeArgsI());
	d2 = READ_FLOAT(runtimeData.outputs, insn.runtimeArgsI() + 1);
	return opXor(d1, d2);
}
[ForceInline]
float evalSmoothAddOp(SdfInstruction insn, SdfProgramRuntimeData runtimeData) {
	float d1; float d2; float k;
	d1 = READ_FLOAT(runtimeData.outputs, insn.runtimeArgsI());
	d2 = READ_FLOAT(runtimeData.outputs, insn.runtimeArgsI() + 1);
	k = READ_FLOAT(sdfProgData[0].args, insn.argsI());
	return opSmoothUnion(d1, d2, k);
}
[ForceInline]
float evalSmoothSubOp(SdfInstruction insn, SdfProgramRuntimeData runtimeData) {
	float d1; float d2; float k;
	d1 = READ_FLOAT(runtimeData.outputs, insn.runtimeArgsI());
	d2 = READ_FLOAT(runtimeData.outputs, insn.runtimeArgsI() + 1);
	k = READ_FLOAT(sdfProgData[0].args, insn.argsI());
	return opSmoothSubtraction(d1, d2, k);
}
[ForceInline]
float evalSmoothInterOp(SdfInstruction insn, SdfProgramRuntimeData runtimeData) {
	float d1; float d2; float k;
	d1 = READ_FLOAT(runtimeData.outputs, insn.runtimeArgsI());
	d2 = READ_FLOAT(runtimeData.outputs, insn.runtimeArgsI() + 1);
	k = READ_FLOAT(sdfProgData[0].args, insn.argsI());
	return opSmoothIntersection(d1, d2, k);
}

// Shapes eval
[ForceInline]
float evalSphere(SdfInstruction insn, float3 rayP) {
	float3 p; float r;
	p = READ_FLOAT3(sdfProgData[0].args, insn.argsI()); r = READ_FLOAT(sdfProgData[0].args, insn.argsI() + 3);
	return sdSphere(rayP - p, r);
}
[ForceInline]
float evalBox(SdfInstruction insn, float3 rayP) {
	float3 p; float3 halfExtent;
	p = READ_FLOAT3(sdfProgData[0].args, insn.argsI()); halfExtent = READ_FLOAT3(sdfProgData[0].args, insn.argsI() + 3);
	return sdBox(rayP - p, halfExtent);
}
[ForceInline]
float evalRoundBox(SdfInstruction insn, float3 rayP) {
	float3 p; float3 halfExtent; float r;
	p = READ_FLOAT3(sdfProgData[0].args, insn.argsI()); halfExtent = READ_FLOAT3(sdfProgData[0].args, insn.argsI() + 3);
	r = READ_FLOAT(sdfProgData[0].args, insn.argsI() + 6);
	return sdRoundBox(rayP - p, halfExtent, r);
}
[ForceInline]
float evalBoxFrame(SdfInstruction insn, float3 rayP) {
	float3 p; float3 b; float e;
	p = READ_FLOAT3(sdfProgData[0].args, insn.argsI()); b = READ_FLOAT3(sdfProgData[0].args, insn.argsI() + 3);
	e = READ_FLOAT(sdfProgData[0].args, insn.argsI() + 6);
	return sdBoxFrame(rayP - p, b, e);
}
[ForceInline]
float evalCone(SdfInstruction insn, float3 rayP) {
	float3 p; float2 c; float h;
	p = READ_FLOAT3(sdfProgData[0].args, insn.argsI()); c = READ_FLOAT2(sdfProgData[0].args, insn.argsI() + 3);
	h = READ_FLOAT(sdfProgData[0].args, insn.argsI() + 5);
	return sdCone(rayP - p, c, h);
}
[ForceInline]
float evalCappedCone(SdfInstruction insn, float3 rayP) {
	float3 p; float3 a; float3 b; float ra; float rb;
	p = READ_FLOAT3(sdfProgData[0].args, insn.argsI()); a = READ_FLOAT3(sdfProgData[0].args, insn.argsI() + 3);
	b = READ_FLOAT3(sdfProgData[0].args, insn.argsI() + 6); ra = READ_FLOAT(sdfProgData[0].args, insn.argsI() + 9);
	rb = READ_FLOAT(sdfProgData[0].args, insn.argsI() + 10);
	return sdCappedCone(rayP - p, a, b, ra, rb);
}
[ForceInline]
float evalHexPrism(SdfInstruction insn, float3 rayP) {
	float3 p; float2 h;
	p = READ_FLOAT3(sdfProgData[0].args, insn.argsI()); h = READ_FLOAT2(sdfProgData[0].args, insn.argsI() + 3);
	return sdHexPrism(rayP - p, h);
}
[ForceInline]
float evalTriPrism(SdfInstruction insn, float3 rayP) {
	float3 p; float2 h;
	p = READ_FLOAT3(sdfProgData[0].args, insn.argsI()); h = READ_FLOAT2(sdfProgData[0].args, insn.argsI() + 3);
	return sdTriPrism(rayP - p, h);
}
[ForceInline]
float evalCapsule(SdfInstruction insn, float3 rayP) {
	float3 p; float3 a; float3 b; float r;
	p = READ_FLOAT3(sdfProgData[0].args, insn.argsI()); a = READ_FLOAT3(sdfProgData[0].args, insn.argsI() + 3);
	b = READ_FLOAT3(sdfProgData[0].args, insn.argsI() + 6);
	r = READ_FLOAT(sdfProgData[0].args, insn.argsI() + 9);
	return sdCapsule(rayP - p, a, b, r);
}
[ForceInline]
float evalCappedCylinder(SdfInstruction insn, float3 rayP) {
	float3 p; float3 a; float3 b; float r;
	p = READ_FLOAT3(sdfProgData[0].args, insn.argsI()); a = READ_FLOAT3(sdfProgData[0].args, insn.argsI() + 3);
	b = READ_FLOAT3(sdfProgData[0].args, insn.argsI() + 6);
	r = READ_FLOAT(sdfProgData[0].args, insn.argsI() + 9);
	return sdCappedCylinder(rayP - p, a, b, r);
}
[ForceInline]
float evalRoundedCylinder(SdfInstruction insn, float3 rayP) {
	float3 p; float ra; float rb; float h;
	p = READ_FLOAT3(sdfProgData[0].args, insn.argsI()); ra = READ_FLOAT(sdfProgData[0].args, insn.argsI() + 3);
	rb = READ_FLOAT(sdfProgData[0].args, insn.argsI() + 4);
	h = READ_FLOAT(sdfProgData[0].args, insn.argsI() + 5);
	return sdRoundedCylinder(rayP - p, ra, rb, h);
}
[ForceInline]
float evalCutSphere(SdfInstruction insn, float3 rayP) {
	float3 p; float r; float h;
	p = READ_FLOAT3(sdfProgData[0].args, insn.argsI()); r = READ_FLOAT(sdfProgData[0].args, insn.argsI() + 3);
	h = READ_FLOAT(sdfProgData[0].args, insn.argsI() + 4);
	return sdCutSphere(rayP - p, r, h);
}
[ForceInline]
float evalOctahedron(SdfInstruction insn, float3 rayP) {
	float3 p; float s;
	p = READ_FLOAT3(sdfProgData[0].args, insn.argsI()); s = READ_FLOAT(sdfProgData[0].args, insn.argsI() + 3);
	return sdOctahedron(rayP - p, s);
}
[ForceInline]
float evalPyramid(SdfInstruction insn, float3 rayP) {
	float3 p; float h;
	p = READ_FLOAT3(sdfProgData[0].args, insn.argsI()); h = READ_FLOAT(sdfProgData[0].args, insn.argsI() + 3);
	return sdPyramid(rayP - p, h);
}
[ForceInline]
float evalTriangle(SdfInstruction insn, float3 rayP) {
	float3 p; float3 a; float3 b; float3 c;
	p = READ_FLOAT3(sdfProgData[0].args, insn.argsI()); a = READ_FLOAT3(sdfProgData[0].args, insn.argsI() + 3);
	b = READ_FLOAT3(sdfProgData[0].args, insn.argsI() + 6); c = READ_FLOAT3(sdfProgData[0].args, insn.argsI() + 9);
	return udTriangle(rayP - p, a, b, c);
}
[ForceInline]
float evalQuad(SdfInstruction insn, float3 rayP) {
	float3 p; float3 a; float3 b; float3 c; float3 d;
	p = READ_FLOAT3(sdfProgData[0].args, insn.argsI()); a = READ_FLOAT3(sdfProgData[0].args, insn.argsI() + 3);
	b = READ_FLOAT3(sdfProgData[0].args, insn.argsI() + 6); c = READ_FLOAT3(sdfProgData[0].args, insn.argsI() + 9);
	d = READ_FLOAT3(sdfProgData[0].args, insn.argsI() + 12);
	return udQuad(rayP - p, a, b, c, d);
}

// TODO: Add passing the correct material through all the evaluations
struct SdfProgramScene : IFloatSdfScene {

	static float sdf(float3 p) {
		uint insnCount, stride; sdfProg.GetDimensions(insnCount, stride);
		SdfProgramRuntimeData runtimeData = {0};
		float res = float.maxValue;
		for (uint i = 0; i < insnCount; i++) {
			SdfInstruction insn = sdfProg[i];

			switch (insn.kind()) {
				case SdfInstructionKind.AddOp: res = evalAddOp(insn, runtimeData); break;
				case SdfInstructionKind.SubOp: res = evalSubOp(insn, runtimeData); break;
				case SdfInstructionKind.InterOp: res = evalInterOp(insn, runtimeData); break;
				case SdfInstructionKind.XorOp: res = evalXorOp(insn, runtimeData); break;
				case SdfInstructionKind.SmoothAddOp: res = evalSmoothAddOp(insn, runtimeData); break;
				case SdfInstructionKind.SmoothSubOp: res = evalSmoothSubOp(insn, runtimeData); break;
				case SdfInstructionKind.SmoothInterOp: res = evalSmoothInterOp(insn, runtimeData); break;
				case SdfInstructionKind.Sphere: res = evalSphere(insn, p); break;
				case SdfInstructionKind.Box: res = evalBox(insn, p); break;
				case SdfInstructionKind.RoundBox: res = evalRoundBox(insn, p); break;
				case SdfInstructionKind.BoxFrame: res = evalBoxFrame(insn, p); break;
				case SdfInstructionKind.Cone: res = evalCone(insn, p); break;
				case SdfInstructionKind.CappedCone: res = evalCappedCone(insn, p); break;
				case SdfInstructionKind.HexPrism: res = evalHexPrism(insn, p); break;
				case SdfInstructionKind.TriPrism: res = evalTriPrism(insn, p); break;
				case SdfInstructionKind.Capsule: res = evalCapsule(insn, p); break;
				case SdfInstructionKind.CappedCylinder: res = evalCappedCylinder(insn, p); break;
				case SdfInstructionKind.RoundedCylinder: res = evalRoundedCylinder(insn, p); break;
				case SdfInstructionKind.CutSphere: res = evalCutSphere(insn, p); break;
				case SdfInstructionKind.Octahedron: res = evalOctahedron(insn, p); break;
				case SdfInstructionKind.Pyramid: res = evalPyramid(insn, p); break;
				case SdfInstructionKind.Triangle: res = evalTriangle(insn, p); break;
				case SdfInstructionKind.Quad: res = evalQuad(insn, p); break;
			}

			WRITE_FLOAT(runtimeData.outputs, insn.outputI(), res);
		}

		return res;
	}

}

// Fancy numeric normal function from https://iquilezles.org/articles/normalsSDF/
float3 calcNormal<T>(T sceneFn, float3 p, float eps) where T : IFloatSdfScene {
  const float2 k = float2(1, -1);
  return normalize(k.xyy * sceneFn.sdf(p + k.xyy * eps) + k.yyx * sceneFn.sdf(p + k.yyx * eps) +
                   k.yxy * sceneFn.sdf(p + k.yxy * eps) + k.xxx * sceneFn.sdf(p + k.xxx * eps));
}

// Slang auto-diff based normal
float3 exactNormal<T>(T sceneFn, in float3 p) where T : IDifferentiableFloatSdfScene {
  float3 normal;
  for (uint axis = 0; axis < 3; axis++) {
    DifferentialPair<float3> dp =
      diffPair(float3(p.x, p.y, p.z), float3(axis == 0 ? 1.0 : 0.0, axis == 1 ? 1.0 : 0.0, axis == 2 ? 1.0 : 0.0));
    DifferentialPair<float> dpOut = fwd_diff(sceneFn.sdf)(dp);
    normal[axis] = dpOut.d;
  }

  return normalize(normal);
}

static const int maxSteps = 128;
Optional<float3> sphereTrace<T>(
	T sceneFn, float3 startPos, float3 rayDir, out float rayDist, out float distToClosest, out uint stepCount,
	float baseHitEps = 1e-6, float farClipDist = 100
) where T : IFloatSdfScene {
	const float minHitEps = 1e-8; // This might be too small
	const float maxHitEps = 1e-1;
	const float maxEpsStepCountScaling = 10000;
  // TODO: Dynamic far clip distance based on sceneFn contents?

  rayDist = 0;
	for (stepCount = 0; stepCount < maxSteps; stepCount++) {
    float3 pos = startPos + rayDir * rayDist;
    distToClosest = sceneFn.sdf(pos);
		// Dynamic ray hit epsilon. Scale by dist to keep ray from missing far away hits and
		// by step budget to prevent missing surfaces at grazing angles. 
		float stepCountScale = 1.0 + maxEpsStepCountScaling * pow(stepCount / float(maxSteps), 10); // On the GPU, pow might be heavy?
		float hitEps = clamp(baseHitEps * rayDist * stepCountScale, minHitEps, maxHitEps); 

    if (distToClosest < hitEps) {
      float3 hitPos = pos + rayDir * distToClosest;
			return hitPos;
    }

    rayDist += distToClosest;
    if (rayDist > farClipDist)
      break;
  }

	return none;
}

void renderScene<T>(T sceneFn, inout FragmentOutput output, float3 rayDirection) where T : IFloatSdfScene {
  // Lighting is hardcoded for now
	const float numericNormalMinEps = 8e-6;

	float rayDist, lastStepLen; uint stepCount;
	var hitOpt = sphereTrace(sceneFn, scene.camPos, rayDirection, rayDist, lastStepLen, stepCount);
	if (hitOpt.hasValue) {
		let hitPos = hitOpt.value;
		// NOTE: Using doubles to calculate normals could make shimmering normals at edges much rarer
		float3 safePos = hitPos - (lastStepLen * rayDirection);
		float3 worldNormal = calcNormal(sceneFn, safePos, max(numericNormalMinEps, 1e-9 * rayDist));

		switch(debugOpt.mode) {
			case RenderMode.BasicLitScene: {
				float3 ambientColor = scene.ambientLightColor * scene.hitColor;
				float3 dirToLight = -scene.mainLightDirection;
				float3 diffuseColor = lambertDiffuse(dirToLight, worldNormal, scene.mainLightColor, scene.hitColor);
				float3 specularColor = blinnPhongSpecular(
					dirToLight, worldNormal, rayDirection, scene.mainLightColor, scene.hitColor, scene.specularExponent
				);
				output.color = float4(ambientColor + diffuseColor + specularColor, 1.0);

				uint lightCount, stride; pointLights.GetDimensions(lightCount, stride);
				for (uint i = 0; i < lightCount; i++) {
					let pointLight = pointLights[i];
					let dirToLight = normalize(pointLight.position - hitPos);
					float3 lightColor = pointLight.getIntensity(hitPos);
					output.color.xyz += lambertDiffuse(dirToLight, worldNormal, lightColor, scene.hitColor);
					output.color.xyz += blinnPhongSpecular(
						dirToLight, worldNormal, rayDirection, lightColor, scene.hitColor, scene.specularExponent
					);
				}
				return;
			}
			case RenderMode.ShadowedLitScene: {
				const float shadowRayHitEps = 0.0001;
				float3 ambientColor = scene.ambientLightColor * scene.hitColor;
				float3 dirToLight = -scene.mainLightDirection;
				let mainLightShadowRayHitOpt = sphereTrace(
					sceneFn, hitPos + worldNormal, dirToLight, rayDist, lastStepLen, stepCount, shadowRayHitEps
				);
				float3 diffuseColor = float3(0); float3 specularColor = float3(0);
				if (!mainLightShadowRayHitOpt.hasValue) {
					diffuseColor = lambertDiffuse(dirToLight, worldNormal, scene.mainLightColor, scene.hitColor);
					specularColor = blinnPhongSpecular(
						dirToLight, worldNormal, rayDirection, scene.mainLightColor, scene.hitColor, scene.specularExponent
					);
				}
				output.color = float4(ambientColor + diffuseColor + specularColor, 1.0);

				uint lightCount, stride; pointLights.GetDimensions(lightCount, stride);
				for (uint i = 0; i < lightCount; i++) {
					let pointLight = pointLights[i];
					float3 lightColor = pointLight.getIntensity(hitPos);
					if (length(lightColor) > 0.001) {
						let vecToLight = pointLight.position - hitPos;
						let dirToLight = normalize(vecToLight);
						let pointLightShadowRayHitOpt = sphereTrace(
							sceneFn, hitPos + worldNormal, dirToLight, rayDist, lastStepLen, stepCount, shadowRayHitEps, length(vecToLight)
						);
						if (!pointLightShadowRayHitOpt.hasValue) {
							output.color.xyz += lambertDiffuse(dirToLight, worldNormal, lightColor, scene.hitColor);
							output.color.xyz += blinnPhongSpecular(
								dirToLight, worldNormal, rayDirection, lightColor, scene.hitColor, scene.specularExponent
							);
						}
					}
				}
				return;
			}
			case RenderMode.UnlitScene:
				output.color = float4(scene.hitColor, 1.0);
				return;
			case RenderMode.DebugNormals:
				output.color = float4(worldNormal, 1.0);
				return;
			case RenderMode.DebugStepCounts:
				float normalizedStepCount = saturate((float)stepCount / maxSteps);
				float3 stepsGradientColor = lerp(float3(0, 1, 0), float3(1, 0, 0), normalizedStepCount);
				output.color = float4(stepsGradientColor, 1);
				return;
		}
	}

  // Set to background color to prevent weird colors for pixels with no hits
  output.color = float4(scene.bgColor, 1.0);
}

// Check the fragment shader code to make sure it matches a basic raytraced camera setup. This was done very quickly to
// see if a fullscreen shader works.
[shader("fragment")]
FragmentOutput fragmentMain(VertexOutput input) {
  FragmentOutput output = (FragmentOutput)0;

  float2 uvNdc = input.fragUv * 2.0 - 1.0;
  uvNdc.x *= scene.aspect;
  float z = 1.0 / tan(radians(scene.fov) * 0.5); // Image plane depth
  float3 rayDirection = normalize(scene.camForward * z + scene.camRight * uvNdc.x + scene.camUp * uvNdc.y);

	renderScene(SdfProgramScene(), output, rayDirection);

  // Ray direction visualization
  // output.color = float4(0.5 * rayDir + 0.5, 1.0);
  return output;
}
