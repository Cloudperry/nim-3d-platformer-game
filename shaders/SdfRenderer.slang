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
  float aspect;
  float3 camPos, camForward, camRight, camUp, hitColor, bgColor;
  float fov;
}

enum RenderMode {
	ShadedScene, UnlitScene, DebugNormals
}

struct DebugSettings {
	RenderMode mode;
}

[[vk::binding(0)]]
ConstantBuffer<SceneUniforms> scene;
[[vk::binding(1)]]
ConstantBuffer<DebugSettings> debugOpt;

[shader("vertex")]
VertexOutput vertexMain(VertexInput input) {
  VertexOutput output;
  output.pos = float4(input.pos, 0.0, 1.0);
  output.fragUv = input.uv;
  return output;
}

// SDF shapes and CSG ops from https://iquilezles.org/articles/distfunctions/

// Sphere - exact
[Differentiable]
T sdSphere<T>(vector<T, 3> p, T r) where T : __BuiltinFloatingPointType {
	return length(p) - r;
}

// Box - exact
[Differentiable]
T sdBox<T>(vector<T, 3> p, vector<T, 3> halfExtent) where T : __BuiltinFloatingPointType {
  vector<T, 3> q = abs(p) - halfExtent;
  return length(max(q, (T)0.0)) + min(max(q.x, max(q.y, q.z)), (T)0.0); // Make a varargs max for max chains like this?
}

// Round box - exact
[Differentiable]
T sdRoundBox<T>(vector<T, 3> p, vector<T, 3> halfExtent, T r) where T : __BuiltinFloatingPointType {
  vector<T, 3> q = abs(p) - halfExtent + r;
  return length(max(q, (T)0.0)) + min(max(q.x, max(q.y, q.z)), (T)0.0) - r;
}

// Box frame - exact
[Differentiable]
T sdBoxFrame<T>(vector<T, 3> p, vector<T, 3> b, T e) where T : __BuiltinFloatingPointType {
  p = abs(p) - b;
  vector<T, 3> q = abs(p+e)-e;
  return min(min(
      length(max(vector<T, 3>(p.x,q.y,q.z), (T)0.0))+min(max(p.x,max(q.y,q.z)), (T)0.0),
      length(max(vector<T, 3>(q.x,p.y,q.z), (T)0.0))+min(max(q.x,max(p.y,q.z)), (T)0.0)),
      length(max(vector<T, 3>(q.x,q.y,p.z), (T)0.0))+min(max(q.x,max(q.y,p.z)), (T)0.0));
}

// Cone - exact
[Differentiable]
T sdCone<T>(vector<T, 3> p, vector<T, 2> c, T h) where T : __BuiltinFloatingPointType {
  // c is the sin/cos of the angle, h is height
  // Alternatively pass q instead of (c,h),
  // which is the point at the base in 2D
  vector<T, 2> q = h*vector<T, 2>(c.x/c.y,-(T)1.0);
    
  vector<T, 2> w = vector<T, 2>( length(p.xz), p.y );
  vector<T, 2> a = w - q*clamp( dot(w,q)/dot(q,q), (T)0.0, (T)1.0);
  vector<T, 2> b = w - q*vector<T, 2>( clamp( w.x/q.x, (T)0.0, (T)1.0 ), (T)1.0 );
  T k = (T)sign( q.y );
  T d = min(dot( a, a ),dot(b, b));
  T s = max( k*(w.x*q.y-w.y*q.x),k*(w.y-q.y)  );
  return sqrt(d) * (T)sign(s);
}

// Hexagonal prism - exact
[Differentiable]
T sdHexPrism<T>(vector<T, 3> p, vector<T, 2> h) where T : __BuiltinFloatingPointType {
  const vector<T, 3> k = vector<T, 3>((T) -0.8660254, (T) 0.5, (T) 0.57735);
  p = abs(p);
  p.xy -= (T) 2.0 * min(dot(k.xy, p.xy), (T) 0.0) * k.xy;
  vector<T, 2> d = vector<T, 2>(
       length(p.xy-vector<T, 2>(clamp(p.x,-k.z*h.x,k.z*h.x), h.x)) * (T) sign(p.y-h.x),
       p.z-h.y );
  return min(max(d.x,d.y), (T) 0.0) + length(max(d, (T) 0.0));
}

// Triangular prism - bound
[Differentiable]
T sdTriPrism<T>( vector<T, 3> p, vector<T, 2> h ) where T : __BuiltinFloatingPointType {
  vector<T, 3> q = abs(p);
  return max(q.z -h.y , max(q.x * (T) 0.866025 + p.y * (T) 0.5, -p.y) -h.x * (T) 0.5);
}

// Arbitrary capsule - exact
[Differentiable]
T sdCapsule<T>( vector<T, 3> p, vector<T, 3> a, vector<T, 3> b, T r ) where T : __BuiltinFloatingPointType {
  vector<T, 3> pa = p - a, ba = b - a;
  T h = clamp( dot(pa,ba) / dot(ba,ba), (T) 0.0, (T) 1.0 );
  return length( pa - ba*h ) - r;
}

// Arbitrary capped cylinder - exact
[Differentiable]
T sdCappedCylinder<T>(vector<T, 3> p, vector<T, 3> a, vector<T, 3> b, T r) where T : __BuiltinFloatingPointType {
  vector<T, 3> ba = b - a;
  vector<T, 3> pa = p - a;
  T baba = dot(ba, ba);
  T paba = dot(pa, ba);
  T x = length(pa * baba - ba * paba) - r * baba;
  T y = abs(paba - baba * (T)0.5) - baba * (T)0.5;
  T x2 = x * x;
  T y2 = y * y * baba;
  T d = (max(x, y) < (T)0.0) ? -min(x2, y2) : (((x > (T)0.0) ? x2 : (T)0.0) + ((y > (T)0.0) ? y2 : (T)0.0));
  return (T)sign(d) * sqrt(abs(d)) / baba;
}

// Rounded cylinder - exact
[Differentiable]
T sdRoundedCylinder<T>( vector<T, 3> p, T ra, T rb, T h ) where T : __BuiltinFloatingPointType {
  vector<T, 2> d = vector<T, 2>( length(p.xz) - (T) 2.0*ra+rb, abs(p.y) - h );
  return min(max(d.x,d.y), (T) 0.0) + length(max(d , (T) 0.0)) - rb;
}

// Arbitrary capped cone - exact
[Differentiable]
T sdCappedCone<T>( vector<T, 3> p, vector<T, 3> a, vector<T, 3> b, T ra, T rb ) where T : __BuiltinFloatingPointType {
  T rba  = rb-ra;
  T baba = dot(b-a,b-a);
  T papa = dot(p-a,p-a);
  T paba = dot(p-a,b-a)/baba;
  T x = sqrt( papa - paba*paba*baba );
  T cax = max((T) 0.0,x-((paba < (T) 0.5)?ra:rb));
  T cay = abs(paba - (T) 0.5) - (T) 0.5;
  T k = rba*rba + baba;
  T f = clamp( (rba*(x-ra)+paba*baba)/k, (T) 0.0, (T) 1.0 );
  T cbx = x-ra - f*rba;
  T cby = paba - f;
  T s = (cbx < (T) 0.0 && cay < (T) 0.0) ? (T) -1.0 : (T) 1.0;
  return s*sqrt( min(cax*cax + cay*cay*baba,
                     cbx*cbx + cby*cby*baba) );
}

// Cut sphere - exact
[Differentiable]
T sdCutSphere<T>( vector<T, 3> p, T r, T h ) where T : __BuiltinFloatingPointType {
  T w = sqrt(r*r-h*h);

  vector<T, 2> q = vector<T, 2>( length(p.xz), p.y );
  T s = max( (h-r)*q.x*q.x+w*w*(h+r - (T) 2.0 * q.y), h*q.x-w*q.y );
  return (s < (T) 0.0) ? length(q)-r :
         (q.x<w) ? h - q.y     :
                   length(q-vector<T, 2>(w,h));
}

// Octahedron - exact
[Differentiable]
T sdOctahedron<T>( vector<T, 3> p, T s ) where T : __BuiltinFloatingPointType {
  p = abs(p);
  T m = p.x+p.y+p.z-s;
  vector<T, 3> q;
       if( (T) 3.0 * p.x < m ) q = p.xyz;
  else if( (T) 3.0 * p.y < m ) q = p.yzx;
  else if( (T) 3.0 * p.z < m ) q = p.zxy;
  else return m * (T) 0.57735027;
    
  T k = clamp((T) 0.5*(q.z-q.y+s), (T) 0.0,s); 
  return length(vector<T, 3>(q.x,q.y-s+k,q.z-k)); 
}

[Differentiable]
// Pyramid - exact
// NOTE: Be careful with this pyramid. It doesn't have a bottom plane, so looking in from the bottom produces completely broken normals.
T sdPyramid<T>(vector<T, 3> p, T h) where T : __BuiltinFloatingPointType {
  T m2 = h * h + (T)0.25;

  p.xz = abs(p.xz);
  p.xz = (p.z > p.x) ? p.zx : p.xz;
  p.xz -= (T)0.5;

  vector<T, 3> q = vector<T, 3>(p.z, h * p.y - (T)0.5 * p.x, h * p.x + (T)0.5 * p.y);

  T s = max(-q.x, (T)0.0);
  T t = clamp((q.y - (T)0.5 * p.z) / (m2 + (T)0.25), (T)0.0, (T)1.0);

  T a = m2 * (q.x + s) * (q.x + s) + q.y * q.y;
  T b = m2 * (q.x + (T)0.5 * t) * (q.x + (T)0.5 * t) + (q.y - m2 * t) * (q.y - m2 * t);

  T d2 = min(q.y, -q.x * m2 - q.y * (T)0.5) > (T)0.0 ? (T)0.0 : min(a, b);

  return sqrt((d2 + q.z * q.z) / m2) * (T)sign(max(q.z, -p.y));
}

T dot2<T>(vector<T, 3> v) where T : __BuiltinFloatingPointType { return dot(v, v); }
// Triangle - exact
[Differentiable]
T udTriangle<T>( vector<T, 3> p, vector<T, 3> a, vector<T, 3> b, vector<T, 3> c ) where T : __BuiltinFloatingPointType {
  vector<T, 3> ba = b - a; vector<T, 3> pa = p - a;
  vector<T, 3> cb = c - b; vector<T, 3> pb = p - b;
  vector<T, 3> ac = a - c; vector<T, 3> pc = p - c;
  vector<T, 3> nor = cross( ba, ac );

  return sqrt(
    ((T) sign(dot(cross(ba,nor),pa)) +
     (T) sign(dot(cross(cb,nor),pb)) +
     (T) sign(dot(cross(ac,nor),pc)) < (T) 2.0)
     ?
     min( min(
     dot2(ba*clamp(dot(ba,pa)/dot2(ba), (T) 0.0, (T) 1.0)-pa),
     dot2(cb*clamp(dot(cb,pb)/dot2(cb), (T) 0.0, (T) 1.0)-pb) ),
     dot2(ac*clamp(dot(ac,pc)/dot2(ac), (T) 0.0, (T) 1.0)-pc) )
     :
     dot(nor,pa)*dot(nor,pa)/dot2(nor) );
}

// Quad - exact
[Differentiable]
T udQuad<T>( vector<T, 3> p, vector<T, 3> a, vector<T, 3> b, vector<T, 3> c, vector<T, 3> d ) where T : __BuiltinFloatingPointType {
  vector<T, 3> ba = b - a; vector<T, 3> pa = p - a;
  vector<T, 3> cb = c - b; vector<T, 3> pb = p - b;
  vector<T, 3> dc = d - c; vector<T, 3> pc = p - c;
  vector<T, 3> ad = a - d; vector<T, 3> pd = p - d;
  vector<T, 3> nor = cross( ba, ad );

	
  return sqrt(
    ((T) sign(dot(cross(ba,nor),pa)) +
     (T) sign(dot(cross(cb,nor),pb)) +
     (T) sign(dot(cross(dc,nor),pc)) +
     (T) sign(dot(cross(ad,nor),pd)) < (T) 3.0)
     ?
     min( min( min(
     dot2(ba*clamp(dot(ba,pa)/dot2(ba), (T) 0.0, (T) 1.0)-pa),
     dot2(cb*clamp(dot(cb,pb)/dot2(cb), (T) 0.0, (T) 1.0)-pb) ),
     dot2(dc*clamp(dot(dc,pc)/dot2(dc), (T) 0.0, (T) 1.0)-pc) ),
     dot2(ad*clamp(dot(ad,pd)/dot2(ad), (T) 0.0, (T) 1.0)-pd) )
     :
     dot(nor,pa)*dot(nor,pa)/dot2(nor) 
	);
}

[Differentiable]
T opUnion<T>(T d1, T d2) where T : __BuiltinFloatingPointType {
	return min(d1, d2);
}
[Differentiable]
T opSubtraction<T>(T d1, T d2) where T : __BuiltinFloatingPointType {
	return max(-d1, d2);
}
[Differentiable]
T opIntersection<T>(T d1, T d2) where T : __BuiltinFloatingPointType {
	return max(d1, d2);
}
[Differentiable]
T opXor<T>(T d1, T d2) where T : __BuiltinFloatingPointType {
	return max(min(d1, d2), -max(d1, d2));
}

[Differentiable]
T opSmoothUnion<T>( T d1, T d2, T k ) where T : __BuiltinFloatingPointType {
    k *= (T) 4.0;
    T h = max(k-abs(d1-d2), (T) 0.0);
    return min(d1, d2) - h*h * (T) 0.25/k;
}

[Differentiable]
T opSmoothSubtraction<T>( T d1, T d2, T k ) where T : __BuiltinFloatingPointType {
    return -opSmoothUnion(d1,-d2,k);
}

[Differentiable]
T opSmoothIntersection<T>( T d1, T d2, T k ) where T : __BuiltinFloatingPointType {
    return -opSmoothUnion(-d1,-d2,k);
}

// TODO: Add rotation/translation and scaling (need function pointers or a way to pass functions as args,
// maybe https://code4k.blogspot.com/2011/11/advanced-hlsl-using-closures-and.html). Mirroring and repetition also
// need functions as args.

// ChatGPT generated test scene
[Differentiable]
float sdSceneChatgptSimple(float3 p) {
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

// Better test scene generated by Claude
[Differentiable]
float sdSceneClaudeBuilding(float3 p) {
  float scene = 1e10;

  // Main building structure
  // Outer walls (large box with hollow interior)
  float outerWalls = sdBox(p, float3(12.0, 4.0, 10.0));
  float innerSpace = sdBox(p, float3(11.5, 3.8, 9.5));
  float walls = opSubtraction(innerSpace, outerWalls);

  // Floor (thin box)
  float floor = sdBox(p - float3(0.0, -3.9, 0.0), float3(12.0, 0.1, 10.0));

  // Ceiling with skylight cutout
  float ceiling = sdBox(p - float3(0.0, 3.9, 0.0), float3(12.0, 0.1, 10.0));
  float skylight1 = sdBox(p - float3(0.0, 4.0, 0.0), float3(2.0, 0.5, 4.0));
  ceiling = opSubtraction(skylight1, ceiling);

  // Support pillars (cylinders)
  float pillar1 = sdCappedCylinder(p - float3(-8.0, 0.0, -6.0), float3(0.0, -3.8, 0.0), float3(0.0, 3.8, 0.0), 0.3);
  float pillar2 = sdCappedCylinder(p - float3(8.0, 0.0, -6.0), float3(0.0, -3.8, 0.0), float3(0.0, 3.8, 0.0), 0.3);
  float pillar3 = sdCappedCylinder(p - float3(-8.0, 0.0, 6.0), float3(0.0, -3.8, 0.0), float3(0.0, 3.8, 0.0), 0.3);
  float pillar4 = sdCappedCylinder(p - float3(8.0, 0.0, 6.0), float3(0.0, -3.8, 0.0), float3(0.0, 3.8, 0.0), 0.3);

  // Central architectural feature - raised platform with stairs
  float platform = sdBox(p - float3(0.0, -3.0, 0.0), float3(3.0, 0.5, 3.0));

  // Stairs (series of boxes)
  float step1 = sdBox(p - float3(0.0, -3.6, -4.0), float3(1.5, 0.2, 0.5));
  float step2 = sdBox(p - float3(0.0, -3.4, -4.5), float3(1.5, 0.4, 0.5));
  float step3 = sdBox(p - float3(0.0, -3.2, -5.0), float3(1.5, 0.6, 0.5));

  // Display pedestals (boxes and cylinders)
  float pedestal1 = sdBox(p - float3(-5.0, -3.0, 0.0), float3(0.8, 0.8, 0.8));
  float pedestal2 = sdCappedCylinder(p - float3(5.0, -2.5, 0.0), float3(0.0, -1.3, 0.0), float3(0.0, 0.0, 0.0), 0.6);
  float pedestal3 = sdBox(p - float3(0.0, -3.0, 5.0), float3(0.6, 0.6, 0.6));

  // Art objects on pedestals (spheres and pyramids)
  float art1 = sdSphere(p - float3(-5.0, -1.5, 0.0), 0.5);
  float art2 = sdPyramid(p - float3(5.0, -1.5, 0.0), 0.8);
  float art3 = sdSphere(p - float3(0.0, -1.8, 5.0), 0.4);

  // Benches (elongated boxes with cutouts)
  float bench1Base = sdBox(p - float3(-3.0, -3.4, -5.0), float3(2.0, 0.3, 0.5));
  float bench1Cutout = sdBox(p - float3(-3.0, -3.4, -5.0), float3(1.7, 0.5, 0.3));
  float bench1 = opSubtraction(bench1Cutout, bench1Base);

  float bench2Base = sdBox(p - float3(3.0, -3.4, -5.0), float3(2.0, 0.3, 0.5));
  float bench2Cutout = sdBox(p - float3(3.0, -3.4, -5.0), float3(1.7, 0.5, 0.3));
  float bench2 = opSubtraction(bench2Cutout, bench2Base);

  // Doorway (subtract from wall)
  float doorway = sdBox(p - float3(0.0, -2.0, -9.8), float3(1.2, 2.0, 1.0));
  walls = opSubtraction(doorway, walls);

  // Windows (subtract from walls)
  float window1 = sdBox(p - float3(-11.8, 0.0, 0.0), float3(1.0, 1.5, 2.0));
  float window2 = sdBox(p - float3(11.8, 0.0, 0.0), float3(1.0, 1.5, 2.0));
  walls = opSubtraction(window1, walls);
  walls = opSubtraction(window2, walls);

  // Decorative wall elements (thin cylinders as columns)
  float decor1 = sdCappedCylinder(p - float3(-11.0, 0.0, -3.0), float3(0.0, -3.5, 0.0), float3(0.0, 3.5, 0.0), 0.15);
  float decor2 = sdCappedCylinder(p - float3(-11.0, 0.0, 3.0), float3(0.0, -3.5, 0.0), float3(0.0, 3.5, 0.0), 0.15);
  float decor3 = sdCappedCylinder(p - float3(11.0, 0.0, -3.0), float3(0.0, -3.5, 0.0), float3(0.0, 3.5, 0.0), 0.15);
  float decor4 = sdCappedCylinder(p - float3(11.0, 0.0, 3.0), float3(0.0, -3.5, 0.0), float3(0.0, 3.5, 0.0), 0.15);

  // Central sculpture (complex CSG)
  float sculptureBase =
    sdCappedCylinder(p - float3(0.0, -1.0, 0.0), float3(0.0, -1.5, 0.0), float3(0.0, 0.0, 0.0), 1.0);
  float sculptureSphere = sdSphere(p - float3(0.0, -0.5, 0.0), 0.8);
  float sculptureBox = sdBox(p - float3(0.0, -0.5, 0.0), float3(0.5, 0.5, 0.5));
  float sculpture = opIntersection(sculptureSphere, sculptureBox);
  sculpture = opUnion(sculpture, sculptureBase);

  // Assemble the scene
  scene = opUnion(walls, floor);
  scene = opUnion(scene, ceiling);
  scene = opUnion(scene, pillar1);
  scene = opUnion(scene, pillar2);
  scene = opUnion(scene, pillar3);
  scene = opUnion(scene, pillar4);
  scene = opUnion(scene, platform);
  scene = opUnion(scene, step1);
  scene = opUnion(scene, step2);
  scene = opUnion(scene, step3);
  scene = opUnion(scene, pedestal1);
  scene = opUnion(scene, pedestal2);
  scene = opUnion(scene, pedestal3);
  scene = opUnion(scene, art1);
  scene = opUnion(scene, art2);
  scene = opUnion(scene, art3);
  scene = opUnion(scene, bench1);
  scene = opUnion(scene, bench2);
  scene = opUnion(scene, sculpture);
  scene = opUnion(scene, decor1);
  scene = opUnion(scene, decor2);
  scene = opUnion(scene, decor3);
  scene = opUnion(scene, decor4);

  return scene;
}

// TODO: Use Slang IFunc interface in sphereTrace, when Slang has improved IFunc to be more usable
[Differentiable]
float sdScene(float3 p) { return sdSceneClaudeBuilding(p); }

// Fancy numeric normal function from https://iquilezles.org/articles/normalsSDF/
float3 calcNormal(in float3 p, float eps) {
  const float2 k = float2(1, -1);
  return normalize(k.xyy * sdScene(p + k.xyy * eps) + k.yyx * sdScene(p + k.yyx * eps) +
                   k.yxy * sdScene(p + k.yxy * eps) + k.xxx * sdScene(p + k.xxx * eps));
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

// TODO: It would probably be better for clarity and performance to just make the ray distance and last step size inout (ref) parameters 
typedef Tuple<float3, float, float> SphereTraceHit;
Optional<SphereTraceHit> sphereTrace(float3 startPos, float3 rayDir) {
  const int maxSteps = 1024;
  const float baseHitDist = 1e-6; // How close to an object should the ray be for it to hit
	// NOTE: Recheck minHitDist and maxHitDist. These distances were setup when the clamping of hitDist was broken (wrong arg order).
	const float minHitDist = 1e-8; // This might be too small
	const float maxHitDist = 1e-2;
  // TODO: Dynamic far clip distance based on scene contents?
  const float farClipDist = 100.0;

  float dist = 0;
	for (uint i = 0; i < maxSteps; i++) {
    float3 pos = startPos + rayDir * dist;
    float distToClosest = sdScene(pos);
		float hitDist = clamp(baseHitDist * dist, minHitDist, maxHitDist); // Dynamic hit distance/epsilon to prevent far away rays from skipping valid hits

    if (distToClosest < hitDist) {
      float3 hitPos = pos + rayDir * distToClosest;
			return makeTuple(hitPos, dist, distToClosest);
    }

    dist += distToClosest;
    if (dist > farClipDist)
      break;
  }

	return none;
}

// Check the fragment shader code to make sure it matches a basic raytraced camera setup. This was done very quickly to
// see if a fullscreen shader works.
[shader("fragment")]
FragmentOutput fragmentMain(VertexOutput input) {
  // Lighting is hardcoded for now
  const float3 lightDirection = normalize(float3(-5.0, -5.0, -3.0));
	const float numericNormalMinEps = 8e-6;
  FragmentOutput output;

  float2 uvNdc = input.fragUv * 2.0 - 1.0;
  uvNdc.x *= scene.aspect;
  float z = 1.0 / tan(radians(scene.fov) * 0.5); // Image plane depth
  float3 rayDirection = normalize(scene.camForward * z + scene.camRight * uvNdc.x + scene.camUp * uvNdc.y);

	var hitOpt = sphereTrace(scene.camPos, rayDirection);
	if (hitOpt.hasValue) {
		let hit = hitOpt.value;
		float3 hitPos = hit._0;
		float hitDist = hit._1;
		float stepDistance = hit._2;
		float3 safePos = hitPos - (stepDistance * rayDirection);
		float3 worldNormalHit = exactNormal(hitPos);
		float3 worldNormalSafe = calcNormal(safePos, max(numericNormalMinEps, 1e-9 * hitDist));
		float3 worldNormal = dot(worldNormalHit, -scene.camForward) > dot(worldNormalSafe, -scene.camForward)
														? worldNormalHit
														: worldNormalSafe;

		float3 diffuseColor = max(dot(worldNormal, -lightDirection), 0.0) * scene.hitColor;

		switch(debugOpt.mode) {
			case RenderMode.ShadedScene:
				output.color = float4(diffuseColor, 1.0);
				return output;
			case RenderMode.UnlitScene:
				output.color = float4(scene.hitColor, 1.0);
				return output;
			case RenderMode.DebugNormals:
				output.color = float4(worldNormal, 1.0);
				return output;
		}
	}

  // Set to background color to prevent weird colors for pixels with no hits
  output.color = float4(scene.bgColor, 1.0);
  // Ray direction visualization
  // output.color = float4(0.5 * rayDir + 0.5, 1.0);
  return output;
}
