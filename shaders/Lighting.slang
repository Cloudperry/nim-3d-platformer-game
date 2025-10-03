module Lighting;

public struct PointLight {
	public float3 position, color;
	public float constTerm, linearFalloff, expFalloff;

	public float3 getIntensity(float3 surfacePos) {
		float distance = length(position - surfacePos);
		float attenuation = 1 / (constTerm + linearFalloff * distance + expFalloff * pow(distance, 2));
		return attenuation * color;
	}
}

public float3 lambertDiffuse(float3 dirToLight, float3 normalVec, float3 lightColor, float3 surfaceColor) {
  float3 diffuseStrength = max(0, dot(normalVec, dirToLight));
  return lightColor * diffuseStrength * surfaceColor;
}

public float3 blinnPhongSpecular(float3 dirToLight, float3 normal, float3 lookDirection,
																 float3 lightColor, float3 surfaceColor, float specularExponent) {
	float normalDotLight = dot(normal, dirToLight);
	// Ignore lights that aren't facing the surface
	if (normalDotLight < 0) return float3(0);

  float3 halfDir = normalize(-lookDirection + dirToLight);
  float specularDot = max(0, dot(normal, halfDir));
  return lightColor * pow(specularDot, specularExponent) * surfaceColor;
}
