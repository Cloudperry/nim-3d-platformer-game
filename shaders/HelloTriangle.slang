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

struct ColorUbo {
  float myColor;
}

[[vk::binding(0)]]
ConstantBuffer<ColorUbo> colorUbo;

[shader("vertex")]
VertexOutput vertexMain(VertexInput input) {
  VertexOutput output;
  output.position = float4(input.position, 1.0);
  output.vertColor = input.color;
  return output;
}

[shader("fragment")]
FragmentOutput fragmentMain(VertexOutput input) {
  FragmentOutput output;
  output.color = float4(input.vertColor, colorUbo.myColor);
  return output;
}
