import std/strformat
import pkg/[glm]
import ./glad/gl
import ./[SceneTypes, Logger]

type
  FpCameraOptions* = object
    # Pitch/yaw scaling to match Source engine. In this engine,
    # transforms use radian rotations so Source engine constants need to be scaled.
    pitchScale*: float = 0.022 * degToRad 
    yawScale*: float = 0.022 * degToRad
    sensitivity*: float = 2
    moveSpeed*: float = 9
    # TODO: Focal length sensitivity scaling for intuitive feeling sensitivity while scoping/changing FOV

proc perspectiveRH*[T](fovy, aspect, zNear, zFar:T): Mat4[T] =
  let tanHalfFovy = tan(fovy / T(2))
  result = mat4[T](0.0)
  result[0,0] = -T(1) / (aspect * tanHalfFovy)
  result[1,1] = -T(1) / (tanHalfFovy)
  result[2,3] = T(-1)

  result[2,2] = -(zFar + zNear) / (zFar - zNear)
  result[3,2] = -(T(2) * zFar * zNear) / (zFar - zNear)

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

proc updateTransform*(e: var Entity) =
  let (forward, _, up) = e.camera.getLocalDirections()
  e.camera.viewMat = lookAt(e.t.pos, e.t.pos + forward, up)

proc moveLocally*(e: var Entity, co: FpCameraOptions, moveDirection: Vec3f, dt: float) =
  let moveBy = moveDirection.normalize() * co.moveSpeed * dt
  let (forward, right, up) = e.camera.getLocalDirections()
  e.t.pos += moveBy.x * right + moveBy.y * up - moveBy.z * forward

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

proc doFlyingCameraMovement*(e: var Entity, co: FpCameraOptions, moveDirection: Vec3f; deltaX, deltaY, dt: float) =
  var tChanged = false
  if moveDirection != vec3f(0):
    # Quick and messy fix for weird feeling vertical movement (doesn't use "correct" move speed)
    let moveDirectionPlane = vec3f(moveDirection.x, 0, moveDirection.z)
    if moveDirectionPlane != vec3f(0):
      e.moveLocally(co, moveDirectionPlane, dt)
    e.t.pos.y += moveDirection.y * co.moveSpeed * dt 
    tChanged = true
  if (deltaX, deltaY) != (0.0, 0.0):
    e.camera.rotate(co, deltaX, -deltaY)
    tChanged = true

  if tChanged:
    e.updateTransform()
    (e.camera.forward, e.camera.right, e.camera.up) = e.camera.getLocalDirections()