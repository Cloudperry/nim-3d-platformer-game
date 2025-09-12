struct VertexInput {
  [[vk::location(0)]]
  float3 position;
  [[vk::location(1)]]
  float3 color;
}

struct VertexOutput {
  float4 position : SV_Position;
  [[vk::location(0)]]
  float3 vertColor;
}

struct FragmentOutput {
  float4 color : SV_Target0;
}

struct Uniforms {
  float4x4 mvp;
  float myColor;
}

[[vk::binding(0)]]
ConstantBuffer<Uniforms> uniforms;

[shader("vertex")]
VertexOutput vertexMain(VertexInput input) {
  VertexOutput output;
  output.position = mul(uniforms.mvp, float4(input.position, 1.0));
  output.vertColor = input.color;
  return output;
}

[shader("fragment")]
FragmentOutput fragmentMain(VertexOutput input) {
  FragmentOutput output;
  output.color = float4(input.vertColor, uniforms.myColor);
  return output;
}
