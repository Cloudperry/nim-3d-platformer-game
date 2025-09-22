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

struct SceneUniforms {
  int2 winResolution;
  float3 camPos, camForward, camRight, camUp;
  float fov;
}

[[vk::binding(0)]]
ConstantBuffer<SceneUniforms> uniforms;

[shader("vertex")]
VertexOutput vertexMain(VertexInput input) {
  VertexOutput output;
  output.pos = float4(input.pos, 0.0, 1.0);
  output.fragUv = input.uv;
  return output;
}

// Check the fragment shader code to make sure it matches a basic raytraced camera setup. This was done very quickly to
// see if a fullscreen shader works.
[shader("fragment")]
FragmentOutput fragmentMain(VertexOutput input) {
  FragmentOutput output;

  float2 uvNdc = input.fragUv * 2.0 - 1.0;
  float aspect = uniforms.winResolution.x / uniforms.winResolution.y;
  uvNdc.x *= aspect;
  float z = 1.0 / tan(radians(uniforms.fov) * 0.5); // Image plane depth
  float3 rayDir = normalize(uniforms.camForward * z + uniforms.camRight * uvNdc.x + uniforms.camUp * uvNdc.y);
  output.color = float4(0.5 * rayDir + 0.5, 1.0);

  return output;
}
