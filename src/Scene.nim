import std/[strformat, options, lenientops]
import ./glad/gl
import pkg/glm
import GlUtils, Logger

# ======================================== Basic transforms ========================================
const degToRad = PI / 180

type
  Transform* = object
    pos*: Vec3f
    scale*: Vec3f = vec3f(1.0, 1.0, 1.0)
    rotation*: Vec3f

proc getTransformMat*(t: Transform): Mat4f =
  var scaleMat, translateMat, rotateMat = mat4f(1.0)
  # Scaling
  scaleMat[0, 0] = t.scale.x
  scaleMat[1, 1] = t.scale.y
  scaleMat[2, 2] = t.scale.z

  # Rotation in X -> Y -> Z order (pitch -> yaw -> roll)
  let (cx, cy, cz) = (cos(t.rotation.x), cos(t.rotation.y), cos(t.rotation.z))
  let (sx, sy, sz) = (sin(t.rotation.x), sin(t.rotation.y), sin(t.rotation.z))
  rotateMat.row0 = vec4f( cy * cz                 , -cy * sz                , sy       , 0.0 )
  rotateMat.row1 = vec4f( sx * sy * cz + cx * sz  , -sx * sy * sz + cx * cz , -sx * cy , 0.0 )
  rotateMat.row2 = vec4f( -cx * sy * cz + sx * sz , cx * sy * sz + sx * cz  , cx * cy  , 0.0 )

  # Translation
  translateMat[3, 0] = t.pos.x
  translateMat[3, 1] = t.pos.y
  translateMat[3, 2] = t.pos.z
  return translateMat * rotateMat * scaleMat

proc perspectiveRH*[T](fovy, aspect, zNear, zFar:T): Mat4[T] =
  let tanHalfFovy = tan(fovy / T(2))
  result = mat4[T](0.0)
  result[0,0] = -T(1) / (aspect * tanHalfFovy)
  result[1,1] = -T(1) / (tanHalfFovy)
  result[2,3] = T(-1)

  result[2,2] = -(zFar + zNear) / (zFar - zNear)
  result[3,2] = -(T(2) * zFar * zNear) / (zFar - zNear)

# ======================================== Camera/player handling ========================================

type
  ProjectionKind* = enum
    Orthographic, Perspective
  FpCameraOptions* = object
    # Pitch/yaw scaling to match Source engine. In this engine,
    # transforms use radian rotations so Source engine constants need to be scaled.
    pitchScale*: float = 0.022 * degToRad 
    yawScale*: float = 0.022 * degToRad
    sensitivity*: float = 2
    moveSpeed*: float = 9
    # TODO: Focal length sensitivity scaling for intuitive feeling sensitivity while scoping/changing FOV
  Camera* = object
    pos*: Vec3f
    # Positive yaw means turning left and positive pitch means turning up
    yaw*: GLfloat = 0 # Start the camera looking forward (toward -Z)
    pitch*: GLfloat = 0
    viewMat*, projectionMat*: Mat4f
    aspectRatio*, nearClip*, farClip*: GLfloat
    forward*: Vec3f = vec3f(0, 0, -1)
    right*: Vec3f = vec3f(1, 0, 0)
    up*: Vec3f = vec3f(0, 1, 0)
    case kind*: ProjectionKind
    of Orthographic:
      frustumLength*: GLfloat
    of Perspective:
      verticalFov*: GLfloat

proc updateProjectionMat*(c: var Camera) =
  case c.kind
  of Orthographic:
    let (frustumW, frustumH) = (c.frustumLength * c.aspectRatio, c.frustumLength)
    c.projectionMat = ortho[GLfloat](
      -frustumW / 2, frustumW / 2,
      -frustumH / 2, frustumH / 2, c.nearClip, c.farClip
    )
  of Perspective:
    c.projectionMat = perspectiveRH[GLfloat](c.verticalFov, c.aspectRatio, c.nearClip, c.farClip)

proc initPerspectiveCamera*(verticalFov, aspectRatio, nearClip, farClip: GLfloat, rasterizerOn: bool): Camera =
  result = Camera(
    kind: Perspective, aspectRatio: aspectRatio, verticalFov: verticalFov,
    nearClip: nearClip, farClip: farClip,
  )
  result.updateProjectionMat()
proc setPerspective*(c: var Camera, verticalFov, aspectRatio, nearClip, farClip: GLfloat) =
  c.kind = Perspective
  c.verticalFov = verticalFov
  c.aspectRatio = aspectRatio
  c.nearClip = nearClip
  c.farClip = farClip
  c.updateProjectionMat()

proc initOrthographicCamera*(frustumLength, aspectRatio, nearClip, farClip: GLfloat): Camera =
  result = Camera(kind: Orthographic, aspectRatio: aspectRatio, frustumLength: frustumLength, nearClip: nearClip, farClip: farClip)
  result.updateProjectionMat()
proc setOrthographic*(c: var Camera, frustumLength, aspectRatio, nearClip, farClip: GLfloat) =
  c.kind = Orthographic
  c.frustumLength = frustumLength
  c.aspectRatio = aspectRatio
  c.nearClip = nearClip
  c.farClip = farClip
  c.updateProjectionMat()

proc getLocalDirections*(c: Camera): tuple[forward, right, up: Vec3f] =
  let
    cosPitch = cos(c.pitch)
    sinPitch = sin(c.pitch)
    # Make camera look forward (-Z) when yaw is 0
    cosYaw = cos(c.yaw + PI / 2)
    sinYaw = sin(c.yaw + PI / 2)
    forward = vec3f(cosPitch * -cosYaw, sinPitch, cosPitch * -sinYaw).normalize()
    right = cross(forward, vec3f(0, 1, 0))
    up = cross(right, forward)
  return (forward, right, up)

proc getCameraViewMat(c: Camera): Mat4f =
  let (forward, _, up) = c.getLocalDirections()
  return lookAt(c.pos, c.pos + forward, up)
proc updateTransform*(c: var Camera) =
  c.viewMat = c.getCameraViewMat()

proc moveLocally*(c: var Camera, co: FpCameraOptions, moveDirection: Vec3f, dt: float) =
  let moveBy = moveDirection.normalize() * co.moveSpeed * dt
  let (forward, right, up) = c.getLocalDirections()
  c.pos += moveBy.x * right + moveBy.y * up - moveBy.z * forward

proc getLocalPlaneMoveDir*(c: var Camera, co: FpCameraOptions, moveDirection: Vec3f): Vec3f =
  let moveDir = moveDirection.normalize() * co.moveSpeed
  let
    cosYaw = cos(c.yaw + PI / 2)
    sinYaw = sin(c.yaw + PI / 2)
    planeForward = vec3f(-cosYaw, 0, -sinYaw).normalize()
    planeRight = cross(planeForward, vec3f(0, 1, 0))
  return moveDir.x * planeRight - moveDir.z * planeForward

proc rotate*(c: var Camera; co: FpCameraOptions, deltaX, deltaY: float) =
  let deltaYaw = deltaX * co.yawScale * co.sensitivity
  let deltaPitch = deltaY * co.pitchScale * co.sensitivity

  c.yaw += deltaYaw
  c.pitch += deltaPitch

  # Prevent vertical flipping
  c.pitch = c.pitch.clamp(-PI / 2 + PI / 256, PI / 2 - PI / 256)
  # Keep yaw in -180 .. 180 degrees
  if c.yaw > PI: c.yaw -= 2 * PI
  if c.yaw < -PI: c.yaw += 2 * PI

proc doFlyingCameraMovement*(c: var Camera, co: FpCameraOptions, moveDirection: Vec3f; deltaX, deltaY, dt: float) =
  var tChanged = false
  if moveDirection != vec3f(0):
    # Quick and messy fix for weird feeling vertical movement (doesn't use "correct" move speed)
    let moveDirectionPlane = vec3f(moveDirection.x, 0, moveDirection.z)
    if moveDirectionPlane != vec3f(0):
      c.moveLocally(co, moveDirectionPlane, dt)
    c.pos.y += moveDirection.y * co.moveSpeed * dt 
    tChanged = true
  if (deltaX, deltaY) != (0.0, 0.0):
    c.rotate(co, deltaX, -deltaY)
    tChanged = true

  if tChanged:
    c.updateTransform()
    (c.forward, c.right, c.up) = c.getLocalDirections()

# ======================================== Models and rasterized scene representation ========================================
const maxVelocity = 88.8888889'f32
# Quake jumping/gravity values
const gravity = 24.0'f32
const jumpImpulse = 8.1'f32
# TODO: Proper DAG-based scene graph with model hierarchies
type 
  ColoredVertex* = object
    pos*, color*, normal*: Vec3f
  # TODO: Add models with textures
  TexturedVertex* = object
    pos*, normal*: Vec3f
    uv*: Vec2f
  Model*[T] = object
    transform*: Transform
    vertices*: seq[T]
    indices*: seq[GLuint] # Indices can be left empty and it means the model has a raw triangle vertex list
  DirectionalLight* = object
    direction*: Vec3f # This should always be normalized
    color*: Vec3f
  Scene*[T] = object
    models*: seq[Model[T]]
    player*: Player
    colliders*: seq[BoxCollider]
    dirLight*: DirectionalLight
    ambientLightColor*: Vec3f

  ColliderTags* = enum
    LevelGeo, Ground, Ignored
  BoxCollider* = object 
    t*: Transform
    halfExtents*: Vec3f
    tags*: set[ColliderTags]
  CollisionResult* = object
    pushVec*: Vec3f
    colliderIds*: seq[int]
  Player* = object
    cam*: Camera
    grounded*: bool
    jumpStart: float32
    velocity*: Vec3f
    collider*: BoxCollider

proc initCollision(pushVec: Vec3f, colliderIds: seq[int] = @[]): CollisionResult =
  CollisionResult(pushVec: pushVec, colliderIds: colliderIds)

makeGlObjects(RaiseError, std140Alignment):
  type
    PointLight* = object
      position*: Vec3f
      color*: Vec3f
      constTerm*, linearFalloff*, expFalloff*: GLfloat
      padding: uint32 # Padding to take the size (as std140) up to 48 bytes. For storing inside UBO array.
      # Point lights should have a max range as well (or alternatively a minimum intensity for the light to be considered visible)

proc move(p: var Player, moveBy: Vec3f) =
  p.cam.pos += moveBy
  p.collider.t.pos += moveBy

proc minPoint(b: BoxCollider): Vec3f = b.t.pos - b.halfExtents
proc maxPoint(b: BoxCollider): Vec3f = b.t.pos + b.halfExtents
proc contains(b: BoxCollider, p: Vec3f): bool =
  let hitboxMin = b.minPoint()
  let hitboxMax = b.maxPoint()
  return p.x in hitboxMin.x .. hitboxMax.x and p.y in hitboxMin.y .. hitboxMax.y and
    p.z in hitboxMin.z .. hitboxMax.z 
proc contains(b1, b2: BoxCollider): bool =
  let b1Min = b1.minPoint()
  let b1Max = b1.maxPoint()
  let b2Min = b2.minPoint()
  let b2Max = b2.maxPoint()
  return not (
    b1Max.x < b2Min.x or b2Max.x < b1Min.x or
    b1Max.y < b2Min.y or b2Max.y < b1Min.y or
    b1Max.z < b2Min.z or b2Max.z < b1Min.z 
  )

proc nextafter(x, y: float64): float64 {.importc, header: "<math.h>".}
proc nextafterf(x, y: float32): float32 {.importc, header: "<math.h>".}
proc nextUp[T: float | float32](x: T): T = nextafter(x, Inf)
proc nextDown[T: float | float32](x: T): T = nextafter(x, -Inf)

proc getPenetrationVector(b1, b2: BoxCollider): Vec3f =
  let 
    overlapX = (b1.halfExtents.x + b2.halfExtents.x) - abs(b1.t.pos.x - b2.t.pos.x)
    overlapY = (b1.halfExtents.y + b2.halfExtents.y) - abs(b1.t.pos.y - b2.t.pos.y)
    overlapZ = (b1.halfExtents.z + b2.halfExtents.z) - abs(b1.t.pos.z - b2.t.pos.z)
  return vec3f(overlapX, overlapY, overlapZ)

proc resolveCollisions(p: var Player, s: Scene): CollisionResult =
  # NOTE: Double check that the logic for leaving player barely inside the collider 
  # makes sense. It is probably wrong in some edge case.
  for i, collider in s.colliders:
    let pen = p.collider.getPenetrationVector(collider)
    if pen.x <= 0 - nextDown(pen.x) or pen.y <= 0 - nextDown(pen.y) or
    pen.z <= 0 - nextDown(pen.z):
      #if p.collider in collider:
        #globalLogger.log fmt"Fake colliding with {s.colliders[i]} with pen {pen}"
      continue

    #globalLogger.log fmt"Colliding with {s.colliders[i]} with pen {pen}"
    if min([pen.x, pen.y, pen.z]) == pen.x:
      let signX = sign(p.collider.t.pos.x - collider.t.pos.x)
      result.pushVec.x += nextDown(pen.x * signX)
      p.velocity.x = 0
    elif min([pen.x, pen.y, pen.z]) == pen.y:
      let signY = sign(p.collider.t.pos.y - collider.t.pos.y)
      result.pushVec.y += nextDown(pen.y * signY)
      p.velocity.y = 0
    else:
      let signZ = sign(p.collider.t.pos.z - collider.t.pos.z)
      result.pushVec.z += nextDown(pen.z * signZ)
      p.velocity.z = 0
    result.colliderIds.add i
    p.move result.pushVec

proc doWalkingPlayerMovement*(p: var Player, s: Scene, co: FpCameraOptions, moveDirection: Vec3f; deltaX, deltaY, dt: float) =
  # Rotation
  if (deltaX, deltaY) != (0.0, 0.0):
    p.cam.rotate(co, deltaX, -deltaY)

  # Movement
  if moveDirection.xz != vec2f(0):
    let moveDirectionPlane = vec3f(moveDirection.x, 0, moveDirection.z)
    if moveDirectionPlane != vec3f(0):
      p.velocity.xz = p.cam.getLocalPlaneMoveDir(co, moveDirectionPlane).xz
    else:
      p.velocity.xz = vec3f(0).xz
  else:
    p.velocity.xz = vec2f(0)
  
  # Jumping and gravity
  if moveDirection.y > 0 and p.grounded:
    globalLogger.log "Jumping, grounded = false"
    p.grounded = false
    p.velocity.y = jumpImpulse
  p.velocity.y -= gravity * dt

  # Apply motion/rotation
  if p.velocity.length() > maxVelocity:
    let velocityNorm = p.velocity.normalize()
    p.velocity = maxVelocity * velocityNorm
  p.move p.velocity * dt

  # Resolve collisions by pushing the player outside a collider if inside
  let collision = p.resolveCollisions(s)
  if collision.pushVec.y != 0:
    globalLogger.log "Hit ground, grounded = true"
    p.grounded = true

  p.cam.updateTransform()
  (p.cam.forward, p.cam.right, p.cam.up) = p.cam.getLocalDirections()

proc posColorNorm*(pos, color, normal: Vec3f): ColoredVertex = ColoredVertex(pos: pos, color: color, normal: normal)
proc posUvNorm*(pos: Vec3f, uv: Vec2f, normal: Vec3f): TexturedVertex = TexturedVertex(pos: pos, uv: uv, normal: normal)

proc initModel*[T](vertices: seq[T], indices: seq[GLuint] = @[], transform = Transform()): Model[T] =
  Model[T](vertices: vertices, indices: indices, transform: transform)

proc initScene*[T](models: seq[Model[T]] = @[], dirLight = DirectionalLight.none, ambientLight = Vec3f.none): Scene[T] =
  result = Scene[T](models: models)
  if dirLight.isSome:
    result.dirLight = dirLight.get
  if ambientLight.isSome:
    result.ambientLightColor = ambientLight.get