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

struct SceneUniforms {
  float3 cameraPos;
  float4x4 modelToWorldMat, worldToViewMat, viewToClipMat;
  float3 mainLightDirection, mainLightColor, ambientLightColor;
}

[[vk::binding(0)]]
ConstantBuffer<SceneUniforms> uniforms;

[shader("vertex")]
VertexOutput vertexMain(VertexInput input) {
  VertexOutput output;
  float4x4 modelToClip =
      mul(uniforms.viewToClipMat,
          mul(uniforms.worldToViewMat, uniforms.modelToWorldMat));
  output.position = mul(modelToClip, float4(input.position, 1.0));
  output.color = input.color;
  output.normal = input.normal;
  return output;
}

[shader("fragment")]
FragmentOutput fragmentMain(VertexOutput input) {
  FragmentOutput output;

  // Get world space normal by ignoring scaling for now. Inverse transpose of
  // modelToWorldMat is required to get correct scaled normals.
  float3 worldNormal = mul((float3x3)(uniforms.modelToWorldMat), input.normal);
  float3 lightDirection = -uniforms.mainLightDirection;
  float3 diffuseColor =
      max(dot(worldNormal, lightDirection), 0.0) * uniforms.mainLightColor;
  output.color = float4(uniforms.ambientLightColor, 1.0f) +
                 float4(diffuseColor, 1.0f) * float4(input.color, 1.0f);

  return output;
}
