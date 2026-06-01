import std/[times, monotimes, strformat, intsets]
import pkg/[glm]
import ./[SceneTypes, Logger, Camera, Physics]

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
  e: var Entity, s: Scene, moveDirection: Vec3f, 
  dt: float, monoTime: MonoTime
) =
  let moveDirectionPlane = vec3f(moveDirection.x, 0, moveDirection.z)
  let targetDir = e.camera.getLocalPlaneMoveDir(moveDirectionPlane)
  let targetSpeed = min(targetDir.length() * maxRunSpeed, maxRunSpeed)

  if monoTime - e.player.lastGroundTouch < coyoteTime:
    e.player.applyGroundFriction(dt)
    e.player.accelerate(targetDir, targetSpeed, accelerationScale, dt)
  else:
    e.player.accelerate(targetDir, targetSpeed, airAccelerationScale, dt)
  
  if moveDirection.y > 0:
    if monoTime - e.player.lastGroundTouch < coyoteTime and not e.player.jumping:
      e.player.jumping = true
      globalLogger.log fmt"Jumping at speed {e.player.velocity.length}, grounded = false"
      e.player.velocity.y += jumpForce
    elif monoTime - e.player.lastWallTouch < coyoteTime and len(e.player.lastTouchedWallColliders * e.player.lastJumpedWallColliders) == 0:
      e.player.lastJumpedWallColliders = e.player.lastTouchedWallColliders
      let rotateAxis = cross(vec3f(0, 1, 0), e.player.lastWallTouchDir)
      let rotateUpMat = rotate(mat4f(), 45.0 * degToRad, rotateAxis)
      let jumpDir = vec4f(e.player.lastWallTouchDir, 0) * rotateUpMat
      globalLogger.log fmt"Wall jumping towards {jumpDir}, grounded = false"
      var cancelVelocity = vec3f(1)
      if e.player.lastWallTouchDir.x != 0: cancelVelocity.x = 0
      if e.player.lastWallTouchDir.y != 0: cancelVelocity.y = 0
      e.player.velocity *= cancelVelocity
      e.player.velocity += 2 * jumpForce * jumpDir.xyz
  e.player.velocity.y -= gravity * dt

  if e.player.velocity.length() > maxVelocity:
    let velocityNorm = e.player.velocity.normalize()
    e.player.velocity = maxVelocity * velocityNorm
  e.t.pos += e.player.velocity * dt

  let collision = e.resolveCollisions(s)
  if collision.colliderIds.len > 0:
    let cosPushVec = collision.pushVec.normalize().y
    if 0.5 <= cosPushVec and cosPushVec <= 1.0:
      e.player.jumping = false
      e.player.lastGroundTouch = monoTime
      e.player.lastTouchedWallColliders.clear()
      e.player.lastJumpedWallColliders.clear()
    elif -0.1 <= cosPushVec and cosPushVec < 0.5:
      e.player.lastWallTouch = monoTime
      e.player.lastTouchedWallColliders = collision.colliderIds.toIntSet()
      e.player.lastWallTouchDir = collision.pushVec.normalize()

  e.updateTransform() # writes correct viewMat into e.camera
  (e.camera.forward, e.camera.right, e.camera.up) = e.camera.getLocalDirections()
