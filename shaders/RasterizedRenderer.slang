struct VertexInput {
  [[vk::location(0)]]
  float3 position;
  [[vk::location(1)]]
  float3 color;
  [[vk::location(2)]]
  float3 normal;
}

struct VertexOutput {
  float4 position : SV_Position;
  [[vk::location(0)]]
  float3 color;
  [[vk::location(1)]]
  float3 normal;
}

struct FragmentOutput {
  float4 color : SV_Target0;
}

struct Uniforms {
  float4x4 mvp;
}

[[vk::binding(0)]]
ConstantBuffer<Uniforms> uniforms;

[shader("vertex")]
VertexOutput vertexMain(VertexInput input) {
  VertexOutput output;
  output.position = mul(uniforms.mvp, float4(input.position, 1.0));
  output.color = input.color;
  output.normal = input.normal;
  return output;
}

[shader("fragment")]
FragmentOutput fragmentMain(VertexOutput input) {
  FragmentOutput output;
  output.color = float4(input.color, 1.0f);
  return output;
}
