import std/strformat
import ./glad/gl
import pkg/glm

const degToRad = PI / 180

type
  Transform* = object
    pos*: Vec3f
    scale*: Vec3f = vec3f(1.0, 1.0, 1.0)
    rotation*: Vec3f
  ProjectionKind* = enum
    Orthographic, Perspective
  FpCameraOptions* = object
    # Pitch/yaw scaling to match Source engine. In this engine,
    # transforms use radian rotations so Source engine constants need to be scaled.
    pitchScale*: float = 0.022 * degToRad 
    yawScale*: float = 0.022 * degToRad
    sensitivity*: float = 2
    moveSpeed*: float = 3
  # TODO: Focal length sensitivity scaling for intuitive feeling sensitivity while scoping/changing FOV
  Camera* = object
    pos*: Vec3f
    yaw*: GLfloat = PI/2 # Start the camera looking forward (toward -Z)
    pitch*: GLfloat
    viewMat*, projectionMat*: Mat4f
    aspectRatio*, nearClip*, farClip*: GLfloat
    case kind*: ProjectionKind
    of Orthographic:
      frustumScale*: GLfloat
    of Perspective:
      verticalFov*: GLfloat

proc updateProjectionMat*(c: var Camera) =
  c.projectionMat = case c.kind
  of Orthographic: ortho[GLfloat](
    -c.frustumScale * c.aspectRatio, c.frustumScale * c.aspectRatio,
    -c.frustumScale, c.frustumScale, c.nearClip, c.farClip
  )
  of Perspective: perspective[GLfloat](c.verticalFov, c.aspectRatio, c.nearClip, c.farClip)

proc initPerspectiveCamera*(verticalFov, aspectRatio, nearClip, farClip: GLfloat): Camera =
  result = Camera(kind: Perspective, aspectRatio: aspectRatio, verticalFov: verticalFov, nearClip: nearClip, farClip: farClip)
  result.updateProjectionMat()
proc setPerspective*(c: var Camera, verticalFov, aspectRatio, nearClip, farClip: GLfloat) =
  c.kind = Perspective
  c.verticalFov = verticalFov
  c.aspectRatio = aspectRatio
  c.nearClip = nearClip
  c.farClip = farClip
  c.updateProjectionMat()

proc initOrthographicCamera*(frustumScale, aspectRatio, nearClip, farClip: GLfloat): Camera =
  Camera(kind: Orthographic, aspectRatio: aspectRatio, frustumScale: frustumScale, nearClip: nearClip, farClip: farClip)
proc setOrthographic*(c: var Camera, frustumScale, aspectRatio, nearClip, farClip: GLfloat) =
  c.kind = Orthographic
  c.frustumScale = frustumScale
  c.aspectRatio = aspectRatio
  c.nearClip = nearClip
  c.farClip = farClip
  c.updateProjectionMat()

proc getTransformMat*(t: Transform): Mat4f =
  var scaleMat, translateMat, rotateMat = mat4f(1.0)
  # Scaling
  scaleMat[0, 0] = t.scale.x
  scaleMat[1, 1] = t.scale.y
  scaleMat[2, 2] = t.scale.z

  # Rotation
  let (cx, cy, cz) = (cos(t.rotation.x), cos(t.rotation.y), cos(t.rotation.z))
  let (sx, sy, sz) = (sin(t.rotation.x), sin(t.rotation.y), sin(t.rotation.z))
  rotateMat[0,0] = cy * cz
  rotateMat[0,1] = -cy * sz
  rotateMat[0,2] = sy
  rotateMat[1,0] = sx * sy * cz + cx * sz
  rotateMat[1,1] = -sx * sy * sz + cx * cz
  rotateMat[1,2] = -sx * cy
  rotateMat[2,0] = -cx * sy * cz + sx * sz
  rotateMat[2,1] = cx * sy * sz + sx * cz
  rotateMat[2,2] = cx * cy

  # Translation
  translateMat[3, 0] = t.pos.x
  translateMat[3, 1] = t.pos.y
  translateMat[3, 2] = t.pos.z
  return translateMat * rotateMat * scaleMat

proc getLocalDirections(c: Camera): tuple[forward, right, up: Vec3f] =
  let
    cosPitch = cos(c.pitch)
    sinPitch = sin(c.pitch)
    cosYaw = cos(c.yaw)
    sinYaw = sin(c.yaw)
    forward = vec3f(cosPitch * cosYaw, sinPitch, cosPitch * -sinYaw).normalize()
    right = cross(forward, vec3f(0, 1, 0)).normalize()
    up = cross(right, forward)
  return (forward, right, up)

proc getCameraViewMat(c: Camera): Mat4f =
  let (forward, right, up) = c.getLocalDirections()
  return lookAt(c.pos, c.pos + forward, up)
proc updateTransform*(c: var Camera) = c.viewMat = c.getCameraViewMat()

proc moveLocally*(c: var Camera, co: FpCameraOptions, moveDirection: Vec3f, dt: float) =
  let moveBy = moveDirection.normalize() * co.moveSpeed * dt
  let (forward, right, up) = c.getLocalDirections()
  let moveByWorldSpace = moveBy.x * right + moveBy.y * up - moveBy.z * forward
  c.pos += moveByWorldSpace

proc rotate*(c: var Camera; co: FpCameraOptions, deltaX, deltaY: float) =
  let deltaYaw = deltaX * co.yawScale * co.sensitivity
  let deltaPitch = deltaY * co.pitchScale * co.sensitivity

  c.yaw += deltaYaw
  c.pitch += deltaPitch

  # Prevent vertical flipping
  c.pitch = c.pitch.clamp(-PI / 2, PI / 2)
  # Keep yaw in -180 .. 180 degrees
  if c.yaw > PI: c.yaw -= 2 * PI
  if c.yaw < -PI: c.yaw += 2 * PI

proc doFirstPersonCameraMovement*(c: var Camera, co: FpCameraOptions, moveDirection: Vec3f; deltaX, deltaY, dt: float) =
  var tChanged = false
  if moveDirection != vec3f(0):
    c.moveLocally(co, moveDirection, dt)
    tChanged = true
  if (deltaX, deltaY) != (0.0, 0.0):
    c.rotate(co, deltaX, deltaY)
    tChanged = true

  if tChanged:
    c.updateTransform()
