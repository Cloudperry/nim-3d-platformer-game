import std/[strformat, options, lenientops, monotimes, intsets]
import std/times except `getTime`
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
  CameraData* = object
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

proc updateProjectionMat*(c: var CameraData) =
  case c.kind
  of Orthographic:
    let (frustumW, frustumH) = (c.frustumLength * c.aspectRatio, c.frustumLength)
    c.projectionMat = ortho[GLfloat](
      -frustumW / 2, frustumW / 2,
      -frustumH / 2, frustumH / 2, c.nearClip, c.farClip
    )
  of Perspective:
    c.projectionMat = perspectiveRH[GLfloat](c.verticalFov, c.aspectRatio, c.nearClip, c.farClip)

proc initPerspectiveCamera*(verticalFov, aspectRatio, nearClip, farClip: GLfloat, rasterizerOn: bool): CameraData =
  result = CameraData(
    kind: Perspective, aspectRatio: aspectRatio, verticalFov: verticalFov,
    nearClip: nearClip, farClip: farClip,
  )
  result.updateProjectionMat()
proc setPerspective*(c: var CameraData, verticalFov, aspectRatio, nearClip, farClip: GLfloat) =
  c.kind = Perspective
  c.verticalFov = verticalFov
  c.aspectRatio = aspectRatio
  c.nearClip = nearClip
  c.farClip = farClip
  c.updateProjectionMat()

proc initOrthographicCamera*(frustumLength, aspectRatio, nearClip, farClip: GLfloat): CameraData =
  result = CameraData(kind: Orthographic, aspectRatio: aspectRatio, frustumLength: frustumLength, nearClip: nearClip, farClip: farClip)
  result.updateProjectionMat()
proc setOrthographic*(c: var CameraData, frustumLength, aspectRatio, nearClip, farClip: GLfloat) =
  c.kind = Orthographic
  c.frustumLength = frustumLength
  c.aspectRatio = aspectRatio
  c.nearClip = nearClip
  c.farClip = farClip
  c.updateProjectionMat()

proc getLocalDirections*(c: CameraData): tuple[forward, right, up: Vec3f] =
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

proc getCameraViewMat(c: CameraData): Mat4f =
  let (forward, _, up) = c.getLocalDirections()
  return lookAt(c.pos, c.pos + forward, up)
proc updateTransform*(c: var CameraData) =
  c.viewMat = c.getCameraViewMat()

proc moveLocally*(c: var CameraData, co: FpCameraOptions, moveDirection: Vec3f, dt: float) =
  let moveBy = moveDirection.normalize() * co.moveSpeed * dt
  let (forward, right, up) = c.getLocalDirections()
  c.pos += moveBy.x * right + moveBy.y * up - moveBy.z * forward

proc getLocalPlaneMoveDir*(c: var CameraData, co: FpCameraOptions, moveDirection: Vec3f): Vec3f =
  let moveDir = moveDirection.normalize() * co.moveSpeed
  let
    cosYaw = cos(c.yaw + PI / 2)
    sinYaw = sin(c.yaw + PI / 2)
    planeForward = vec3f(-cosYaw, 0, -sinYaw).normalize()
    planeRight = cross(planeForward, vec3f(0, 1, 0))
  return moveDir.x * planeRight - moveDir.z * planeForward

proc rotate*(c: var CameraData; co: FpCameraOptions, deltaX, deltaY: float) =
  let deltaYaw = deltaX * co.yawScale * co.sensitivity
  let deltaPitch = deltaY * co.pitchScale * co.sensitivity

  c.yaw += deltaYaw
  c.pitch += deltaPitch

  # Prevent vertical flipping
  c.pitch = c.pitch.clamp(-PI / 2 + PI / 256, PI / 2 - PI / 256)
  # Keep yaw in -180 .. 180 degrees
  if c.yaw > PI: c.yaw -= 2 * PI
  if c.yaw < -PI: c.yaw += 2 * PI

proc doFlyingCameraMovement*(c: var CameraData, co: FpCameraOptions, moveDirection: Vec3f; deltaX, deltaY, dt: float) =
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
const
  maxVelocity = 88.8888889'f32
  # Quake jumping/gravity values. Might be too fast with bhopping.
  gravity = 24.0'f32
  jumpForce = 8.1'f32
  coyoteTime = initDuration(milliseconds = 50)
  maxRunSpeed = 6.10'f32
  accelerationScale = 10'f32
  airAccelerationScale = 10'f32
  frictionScale = 4'f32
  stopSpeed = 1.905'f32
  forwardSpeed = 7.62'f32
  sideSpeed = 7.62'f32

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
    entities*: seq[Entity]
    player*: PlayerData
    colliders*: seq[BoxColliderData]
    dirLight*: DirectionalLight
    ambientLightColor*: Vec3f
  EntityId* = object
    id*: int
    generation*: uint8
  EntityKind* = enum
    Root, Base, Player, Camera, BoxCollider
  Entity* = object
    kind*: EntityKind
    t*: Transform
    # Parent/child data could be just one table in Scene that holds information about all entities
    parentIds*: seq[EntityId]
    childIds*: seq[EntityId]
    playerData: Option[PlayerData]
    cameraData: Option[CameraData]
    boxColliderData: Option[BoxColliderData]

  ColliderTags* = enum
    LevelGeo, Ground, Ignored
  BoxColliderData* = object 
    halfExtents*: Vec3f
    tags*: set[ColliderTags] = {LevelGeo}
  CollisionResult* = object
    pushVec*: Vec3f
    colliderIds*: seq[int]
  PlayerData* = object
    jumping*: bool
    lastWallTouch*, lastGroundTouch*: MonoTime
    lastWallTouchDir*: Vec3f
    lastTouchedWallColliders*, lastJumpedWallColliders*: IntSet
    velocity*: Vec3f
    collider*: BoxColliderData

template addSafeComponentAccessors(fieldName: untyped, hiddenFieldName: untyped, allowedKinds: set[EntityKind]): untyped =
  proc fieldName*(e: Entity): auto =
    assert e.kind in allowedKinds, "This entity doesn't have this field"
    e.hiddenFieldName.get
  proc `fieldName=`*(e: var Entity, val: auto) =
    assert e.kind in allowedKinds, "This entity doesn't have this field"
    e.hiddenFieldName.get = val

addSafeComponentAccessors(player, playerData, {Player})
addSafeComponentAccessors(camera, cameraData, {Player, Camera})
addSafeComponentAccessors(boxCollider, boxColliderData, {Player, BoxCollider})

let rootNode = Entity(kind: Root)
const rootId = EntityId(id: 0, generation: 0)

proc initPlayerE(t: Transform, p: PlayerData, c: CameraData, bc: BoxColliderData): Entity =
  Entity(kind: Player, t: t, playerData: some p, cameraData: some c, boxColliderData: some bc, parentIds: @[rootID])
proc initBoxColliderE(t: Transform, bc: BoxColliderData): Entity =
  Entity(kind: BoxCollider, t: t, boxColliderData: some bc, parentIds: @[rootId])

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

proc minPoint(e: Entity): Vec3f = e.t.pos - e.boxCollider.halfExtents
proc maxPoint(e: Entity): Vec3f = e.t.pos + e.boxCollider.halfExtents
proc contains(e: Entity, p: Vec3f): bool =
  let hitboxMin = e.minPoint()
  let hitboxMax = e.maxPoint()
  return p.x in hitboxMin.x .. hitboxMax.x and p.y in hitboxMin.y .. hitboxMax.y and
    p.z in hitboxMin.z .. hitboxMax.z 
proc contains(e1, e2: Entity): bool =
  let b1Min = e1.minPoint()
  let b1Max = e1.maxPoint()
  let b2Min = e2.minPoint()
  let b2Max = e2.maxPoint()
  return not (
    b1Max.x < b2Min.x or b2Max.x < b1Min.x or
    b1Max.y < b2Min.y or b2Max.y < b1Min.y or
    b1Max.z < b2Min.z or b2Max.z < b1Min.z 
  )

proc nextafter(x, y: float64): float64 {.importc, header: "<math.h>".}
proc nextafterf(x, y: float32): float32 {.importc, header: "<math.h>".}
proc nextUp[T: float | float32](x: T): T = nextafter(x, Inf)
proc nextDown[T: float | float32](x: T): T = nextafter(x, -Inf)

proc getPenetrationVector(e1, e2: Entity): Vec3f =
  let (b1, b2) = (e1.boxCollider, e2.boxCollider)
  let 
    overlapX = (b1.halfExtents.x + b2.halfExtents.x) - abs(e1.t.pos.x - e2.t.pos.x)
    overlapY = (b1.halfExtents.y + b2.halfExtents.y) - abs(e1.t.pos.y - e2.t.pos.y)
    overlapZ = (b1.halfExtents.z + b2.halfExtents.z) - abs(e1.t.pos.z - e2.t.pos.z)
  return vec3f(overlapX, overlapY, overlapZ)

proc resolveCollisions(p: var PlayerData, s: Scene): CollisionResult =
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

proc applyGroundFriction*(p: var PlayerData, dt: float) =
  let speed = p.velocity.length()

  if speed < 0.05'f32: 
    p.velocity = vec3f(0)
  else:
    let control = if speed < stopSpeed: stopSpeed else: speed
    let speedLoss = control * frictionScale * dt
    let newSpeed = max(0.0, speed - speedLoss)
    p.velocity *= newSpeed / speed

proc accelerate(p: var PlayerData, targetDir: Vec3f, targetSpeed, accel: float32; dt: float) =
  let speedTowardsTarget = p.velocity.dot(targetDir)
  let addSpeed = targetSpeed - speedTowardsTarget
  if addSpeed > 0:
    let accelSpeed = min(accel * targetSpeed * dt.float32, addSpeed)
    p.velocity += accelSpeed * targetDir

proc doWalkingPlayerMovement*(
  p: var PlayerData, s: Scene, co: FpCameraOptions, moveDirection: Vec3f; 
  deltaX, deltaY, dt: float, monoTime: MonoTime
) =
  # Rotation
  if (deltaX, deltaY) != (0.0, 0.0):
    p.cam.rotate(co, deltaX, -deltaY)

  # Movement
  let moveDirectionPlane = vec3f(moveDirection.x, 0, moveDirection.z)
  # The function getLocalPlane... always returns normalized values. If controller inputs are added,
  # they are not normalized and they should be normalized right before being used with accelerate.  
  let targetDir = p.cam.getLocalPlaneMoveDir(co, moveDirectionPlane).normalize()
  let targetSpeed = min(targetDir.length() * maxRunSpeed, maxRunSpeed)

  if monoTime - p.lastGroundTouch < coyoteTime: # This should probably be a real collision check
    p.applyGroundFriction(dt)
    p.accelerate(targetDir, targetSpeed, accelerationScale, dt)
  else:
    p.accelerate(targetDir, targetSpeed, airAccelerationScale, dt)
  
  # Jumping and gravity
  if moveDirection.y > 0:
    if monoTime - p.lastGroundTouch < coyoteTime and not p.jumping:
      p.jumping = true
      globalLogger.log fmt"Jumping at speed {p.velocity.length}, grounded = false"
      p.velocity.y += jumpForce
    elif monoTime - p.lastWallTouch < coyoteTime and len(p.lastTouchedWallColliders * p.lastJumpedWallColliders) == 0:
      p.lastJumpedWallColliders = p.lastTouchedWallColliders
      let rotateAxis = cross(vec3f(0, 1, 0), p.lastWallTouchDir)
      let rotateUpMat = rotate(mat4f(), 45.0 * degToRad, rotateAxis)
      let jumpDir = vec4f(p.lastWallTouchDir, 0) * rotateUpMat
      globalLogger.log fmt"Wall jumping towards {jumpDir}, grounded = false"
      var cancelVelocity = vec3f(1)
      if p.lastWallTouchDir.x != 0: cancelVelocity.x = 0
      if p.lastWallTouchDir.y != 0: cancelVelocity.y = 0
      p.velocity *= cancelVelocity
      p.velocity += 2 * jumpForce * jumpDir.xyz
  p.velocity.y -= gravity * dt

  # Apply motion/rotation
  if p.velocity.length() > maxVelocity:
    let velocityNorm = p.velocity.normalize()
    p.velocity = maxVelocity * velocityNorm
  p.move p.velocity * dt

  # Resolve collisions by pushing the player outside a collider if inside
  let collision = p.resolveCollisions(s)
  if collision.colliderIds.len > 0:
    let cosPushVec = collision.pushVec.normalize().y
    if 0.5 <= cosPushVec and cosPushVec <= 1.0: # Can jump from 0-45 degrees slopes
      p.jumping = false
      p.lastGroundTouch = monoTime
      p.lastTouchedWallColliders.clear()
      p.lastJumpedWallColliders.clear()
    elif -0.1 <= cosPushVec and cosPushVec < 0.5: # Can walljump from 45 degree slopes and up to vertical walls
      p.lastWallTouch = monoTime
      p.lastTouchedWallColliders = collision.colliderIds.toIntSet()
      p.lastWallTouchDir = collision.pushVec.normalize()

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