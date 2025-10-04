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

// Interleaved gradient noise by Jorge Jimenez from Call of Duty: Advanced Warfare (found from https://blog.frost.kiwi/GLSL-noise-and-radial-gradient/)
public float gradientNoise(float2 uv) {
	return fract(52.9829189 * fract(dot(uv, float2(0.06711056, 0.00583715))));
}

public float gradientNoiseWithStrength(float2 uv, float strength) {
	return (strength / 255.0) * gradientNoise(uv) - (strength / 2 / 255.0);
}
