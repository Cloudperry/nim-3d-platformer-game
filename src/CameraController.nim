import pkg/[glm]
import ./glad/gl
import ./[SceneTypes]

proc perspectiveRH*[T](fovy, aspect, zNear, zFar: T): Mat4[T] =
  ## Builds a right-handed perspective projection matrix. The signs are flipped compared
  ## to a standard glm perspective to match this engine's coordinate conventions.
  let tanHalfFovy = tan(fovy / T(2))
  result = mat4[T](0.0)
  result[0, 0] = -T(1) / (aspect * tanHalfFovy)
  result[1, 1] = -T(1) / (tanHalfFovy)
  result[2, 3] = T(-1)

  result[2, 2] = -(zFar + zNear) / (zFar - zNear)
  result[3, 2] = -(T(2) * zFar * zNear) / (zFar - zNear)

proc updateProjectionMat*(c: var CameraData) =
  ## Recomputes the camera's projection matrix from its current settings. Call this after
  ## changing the aspect ratio, FOV or clip planes (e.g. on window resize).
  case c.kind
  of Orthographic:
    let (frustumW, frustumH) = (c.frustumLength * c.aspectRatio, c.frustumLength)
    c.projectionMat = ortho[GLfloat](
      -frustumW / 2, frustumW / 2, -frustumH / 2, frustumH / 2, c.nearClip, c.farClip
    )
  of Perspective:
    c.projectionMat =
      perspectiveRH[GLfloat](c.verticalFov, c.aspectRatio, c.nearClip, c.farClip)

proc initPerspectiveCamera*(
    verticalFov, aspectRatio, nearClip, farClip: GLfloat
): CameraData =
  ## Creates a perspective camera and computes its initial projection matrix.
  result = CameraData(
    kind: Perspective,
    aspectRatio: aspectRatio,
    verticalFov: verticalFov,
    nearClip: nearClip,
    farClip: farClip,
  )
  result.updateProjectionMat()

proc initOrthographicCamera*(
    frustumLength, aspectRatio, nearClip, farClip: GLfloat
): CameraData =
  result = CameraData(
    kind: Orthographic,
    aspectRatio: aspectRatio,
    frustumLength: frustumLength,
    nearClip: nearClip,
    farClip: farClip,
  )
  result.updateProjectionMat()

proc getLocalDirections*(c: CameraData): tuple[forward, right, up: Vec3f] =
  ## Computes the camera's local forward/right/up basis vectors from its yaw and pitch.
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
  ## Refreshes the camera's direction vectors and view matrix to match the entity's
  ## current position and rotation. Call this whenever the player moves or turns.
  (e.camera.forward, e.camera.right, e.camera.up) = e.camera.getLocalDirections()
  e.camera.viewMat = lookAt(e.t.pos, e.t.pos + e.camera.forward, e.camera.up)

proc moveLocally*(e: var Entity, co: FpCameraOptions, moveDirection: Vec3f, dt: float) =
  let moveBy = moveDirection.normalize() * co.moveSpeed * dt
  let (forward, right, up) = e.camera.getLocalDirections()
  e.t.pos += moveBy.x * right + moveBy.y * up - moveBy.z * forward

proc getLocalPlaneMoveDir*(c: var CameraData, moveDirection: Vec3f): Vec3f =
  ## Maps a local input move direction onto the horizontal (XZ) plane using the camera's
  ## yaw, ignoring pitch. Used for ground movement so looking up/down doesn't affect speed.
  let moveDir = moveDirection.normalize()
  let
    cosYaw = cos(c.yaw + PI / 2)
    sinYaw = sin(c.yaw + PI / 2)
    planeForward = vec3f(-cosYaw, 0, -sinYaw).normalize()
    planeRight = cross(planeForward, vec3f(0, 1, 0))
  return moveDir.x * planeRight - moveDir.z * planeForward

proc rotate*(c: var CameraData, co: FpCameraOptions, deltaX, deltaY: float) =
  ## Applies mouse deltas to the camera's yaw and pitch. Pitch is clamped to avoid
  ## flipping over and yaw is kept within -180..180 degrees.
  let deltaYaw = deltaX * co.yawScale * co.sensitivity
  let deltaPitch = deltaY * co.pitchScale * co.sensitivity

  c.yaw += deltaYaw
  c.pitch += deltaPitch

  # Prevent vertical flipping
  c.pitch = c.pitch.clamp(-PI / 2 + PI / 256, PI / 2 - PI / 256)
  # Keep yaw in -180 .. 180 degrees
  if c.yaw > PI:
    c.yaw -= 2 * PI
  if c.yaw < -PI:
    c.yaw += 2 * PI

proc doCameraRotation*(e: var Entity, deltaX, deltaY: float, co: FpCameraOptions) =
  ## Rotates the camera from mouse input and updates the transform if anything changed.
  if (deltaX, deltaY) != (0.0, 0.0):
    e.camera.rotate(co, deltaX, -deltaY)
    e.updateTransform()

proc doFlyingCameraMovement*(e: var Entity, co: FpCameraOptions, dt: float) =
  ## Moves a free-flying (noclip) camera based on the current move direction. Horizontal
  ## movement uses the camera's local plane directions and vertical movement is world up/down.
  if e.player.moveDirection != vec3f(0):
    # Quick and messy fix for weird feeling vertical movement (doesn't use "correct" move speed)
    let moveDirectionPlane =
      vec3f(e.player.moveDirection.x, 0, e.player.moveDirection.z)
    if moveDirectionPlane != vec3f(0):
      e.moveLocally(co, moveDirectionPlane, dt)
    e.t.pos.y += e.player.moveDirection.y * co.moveSpeed * dt
    e.updateTransform()
