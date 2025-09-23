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
  float3 camPos, camForward, camRight, camUp, hitColor, bgColor;
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

// SDF shapes and CSG ops from https://iquilezles.org/articles/distfunctions/

[Differentiable]
float sdSphere(float3 p, float r) { return length(p) - r; }
[Differentiable]
float sdBox(float3 p, float3 halfExtent) {
  float3 q = abs(p) - halfExtent;
  return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0); // Make a varargs max for max chains like this?
}
[Differentiable]
float sdCappedCylinder(float3 p, float3 a, float3 b, float r) {
  float3 ba = b - a;
  float3 pa = p - a;
  float baba = dot(ba, ba);
  float paba = dot(pa, ba);
  float x = length(pa * baba - ba * paba) - r * baba;
  float y = abs(paba - baba * 0.5) - baba * 0.5;
  float x2 = x * x;
  float y2 = y * y * baba;
  float d = (max(x, y) < 0.0) ? -min(x2, y2) : (((x > 0.0) ? x2 : 0.0) + ((y > 0.0) ? y2 : 0.0));
  return sign(d) * sqrt(abs(d)) / baba;
}
[Differentiable]
float sdPyramid(float3 p, float h) {
  float m2 = h * h + 0.25;

  p.xz = abs(p.xz);
  p.xz = (p.z > p.x) ? p.zx : p.xz;
  p.xz -= 0.5;

  float3 q = float3(p.z, h * p.y - 0.5 * p.x, h * p.x + 0.5 * p.y);

  float s = max(-q.x, 0.0);
  float t = clamp((q.y - 0.5 * p.z) / (m2 + 0.25), 0.0, 1.0);

  float a = m2 * (q.x + s) * (q.x + s) + q.y * q.y;
  float b = m2 * (q.x + 0.5 * t) * (q.x + 0.5 * t) + (q.y - m2 * t) * (q.y - m2 * t);

  float d2 = min(q.y, -q.x * m2 - q.y * 0.5) > 0.0 ? 0.0 : min(a, b);

  return sqrt((d2 + q.z * q.z) / m2) * sign(max(q.z, -p.y));
}

[Differentiable]
float opUnion(float d1, float d2) { return min(d1, d2); }
[Differentiable]
float opSubtraction(float d1, float d2) { return max(-d1, d2); }
[Differentiable]
float opIntersection(float d1, float d2) { return max(d1, d2); }
[Differentiable]
float opXor(float d1, float d2) { return max(min(d1, d2), -max(d1, d2)); }

// ChatGPT generated test scene
[Differentiable]
float sdScene(float3 p) {
  // Shift scene down a bit
  p.y += 0.5;

  // Ground plane (big flat box)
  float dGround = sdBox(p + float3(0, 1.0, 0), float3(10.0, 0.5, 10.0));

  // Central sphere cluster
  float dSphere1 = sdSphere(p - float3(0, 0, -3), 1.0);
  float dSphere2 = sdSphere(p - float3(1.5, 0.2, -2.5), 0.6);
  float dSphere3 = sdSphere(p - float3(-1.5, -0.2, -2.5), 0.6);
  float dCluster = opUnion(dSphere1, opUnion(dSphere2, dSphere3));

  // Box tower with subtraction
  float dBoxBase = sdBox(p - float3(-3, 0.0, -4), float3(0.7, 1.2, 0.7));
  float dBoxHole = sdSphere(p - float3(-3, 0.0, -4), 0.8);
  float dBoxTower = opSubtraction(dBoxBase, dBoxHole);

  // Pyramid intersected with sphere
  float dPyramid = sdPyramid(p - float3(3, 0.0, -4), 1.5);
  float dPySphere = sdSphere(p - float3(3, 0.0, -4), 1.0);
  float dPyramidShape = opIntersection(dPyramid, dPySphere);

  // Cylinders forming a "cross"
  float dCyl1 = sdCappedCylinder(p, float3(0, -1, -6), float3(0, 1, -6), 0.3);
  float dCyl2 = sdCappedCylinder(p, float3(-1, 0, -6), float3(1, 0, -6), 0.3);
  float dCross = opUnion(dCyl1, dCyl2);

  // Combine all
  float scene = opUnion(dGround, opUnion(dCluster, opUnion(dBoxTower, opUnion(dPyramidShape, dCross))));

  return scene;
}

[Differentiable]
float sdSceneDiff(float x, float y, float z) {
  float3 p = float3(x, y, z);
  return sdScene(p);
}

// Fancy numeric normal function from https://iquilezles.org/articles/normalsSDF/
float3 calcNormal(in float3 p) {
  const float h = 0.0001; // replace by an appropriate value
  const float2 k = float2(1, -1);
  return normalize(k.xyy * sdScene(p + k.xyy * h) + k.yyx * sdScene(p + k.yyx * h) + k.yxy * sdScene(p + k.yxy * h) +
                   k.xxx * sdScene(p + k.xxx * h));
}

// Slang auto-diff based normal
float3 exactNormal(in float3 p) {
  float3 normal;
  for (uint axis = 0; axis < 3; axis++) {
    DifferentialPair<float3> dp =
        diffPair(float3(p.x, p.y, p.z), float3(axis == 0 ? 1.0 : 0.0, axis == 1 ? 1.0 : 0.0, axis == 2 ? 1.0 : 0.0));
    DifferentialPair<float> dpOut = fwd_diff(sdScene)(dp);
    normal[axis] = dpOut.d;
  }

  return normalize(normal);
}

// Check the fragment shader code to make sure it matches a basic raytraced camera setup. This was done very quickly to
// see if a fullscreen shader works.
[shader("fragment")]
FragmentOutput fragmentMain(VertexOutput input) {
  const int maxSteps = 512;
  const float hitDistance = 0.001;
  // TODO: Dynamic far clip distance based on scene contents?
  const float farClipDist = 100.0;
  // Lighting is hardcoded for now
  const float3 lightDirection = normalize(float3(-5.0, -5.0, -3.0));

  FragmentOutput output;

  float2 uvNdc = input.fragUv * 2.0 - 1.0;
  float aspect = (float)uniforms.winResolution.x / (float)uniforms.winResolution.y;
  uvNdc.x *= aspect;
  float z = 1.0 / tan(radians(uniforms.fov) * 0.5); // Image plane depth
  float3 rayDir = normalize(uniforms.camForward * z + uniforms.camRight * uvNdc.x + uniforms.camUp * uvNdc.y);
  float dist = 0;

  for (uint i = 0; i < maxSteps; i++) {
    float3 pos = uniforms.camPos + rayDir * dist;
    float distToClosest = sdScene(pos);

    if (distToClosest < hitDistance) {
      float3 posNext = uniforms.camPos + rayDir * (dist + distToClosest);
      float3 worldNormal = exactNormal(posNext);
      float3 diffuseColor = max(dot(worldNormal, -lightDirection), 0.0) * uniforms.hitColor;
      output.color = float4(diffuseColor, 1.0);
      // Unlit objects:
      // output.color = float4(uniforms.hitColor, 1.0);
      return output;
    }

    dist += distToClosest;
    if (dist > farClipDist)
      break;
  }

  // Set to background color to prevent weird colors for pixels with no hits
  output.color = float4(uniforms.bgColor, 1.0);
  // Ray direction visualization
  // output.color = float4(0.5 * rayDir + 0.5, 1.0);

  return output;
}
