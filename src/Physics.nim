import pkg/[glm]
import ./[SceneTypes]

proc initCollision(pushVec: Vec3f, colliderIds: seq[int] = @[]): CollisionResult =
  CollisionResult(pushVec: pushVec, colliderIds: colliderIds)

proc minPoint(e: Entity): Vec3f =
  e.t.pos - e.boxCollider.halfExtents

proc maxPoint(e: Entity): Vec3f =
  e.t.pos + e.boxCollider.halfExtents

proc contains(e: Entity, p: Vec3f): bool =
  let hitboxMin = e.minPoint()
  let hitboxMax = e.maxPoint()
  return
    p.x in hitboxMin.x .. hitboxMax.x and p.y in hitboxMin.y .. hitboxMax.y and
    p.z in hitboxMin.z .. hitboxMax.z

proc contains(e1, e2: Entity): bool =
  let b1Min = e1.minPoint()
  let b1Max = e1.maxPoint()
  let b2Min = e2.minPoint()
  let b2Max = e2.maxPoint()
  return not (
    b1Max.x < b2Min.x or b2Max.x < b1Min.x or b1Max.y < b2Min.y or b2Max.y < b1Min.y or
    b1Max.z < b2Min.z or b2Max.z < b1Min.z
  )

proc nextafter(x, y: float64): float64 {.importc, header: "<math.h>".}
proc nextafterf(x, y: float32): float32 {.importc, header: "<math.h>".}
proc nextUp[T: float | float32](x: T): T =
  nextafter(x, Inf)

proc nextDown[T: float | float32](x: T): T =
  nextafter(x, -Inf)

proc getPenetrationVector(e1, e2: Entity): Vec3f =
  let (b1, b2) = (e1.boxCollider, e2.boxCollider)
  let
    overlapX = (b1.halfExtents.x + b2.halfExtents.x) - abs(e1.t.pos.x - e2.t.pos.x)
    overlapY = (b1.halfExtents.y + b2.halfExtents.y) - abs(e1.t.pos.y - e2.t.pos.y)
    overlapZ = (b1.halfExtents.z + b2.halfExtents.z) - abs(e1.t.pos.z - e2.t.pos.z)
  return vec3f(overlapX, overlapY, overlapZ)

proc resolveCollisions*(e: var Entity, s: Scene): CollisionResult =
  # NOTE: Double check that the logic for leaving player barely inside the collider 
  # makes sense. It is probably wrong in some edge case.
  for i in s.colliderIds:
    let collider = s.entities[i]
    let pen = e.getPenetrationVector(collider)
    if pen.x <= 0 - nextDown(pen.x) or pen.y <= 0 - nextDown(pen.y) or
        pen.z <= 0 - nextDown(pen.z):
      continue

    if min([pen.x, pen.y, pen.z]) == pen.x:
      let signX = sign(e.t.pos.x - collider.t.pos.x)
      result.pushVec.x += nextDown(pen.x * signX)
      e.player.velocity.x = 0
    elif min([pen.x, pen.y, pen.z]) == pen.y:
      let signY = sign(e.t.pos.y - collider.t.pos.y)
      result.pushVec.y += nextDown(pen.y * signY)
      e.player.velocity.y = 0
    else:
      let signZ = sign(e.t.pos.z - collider.t.pos.z)
      result.pushVec.z += nextDown(pen.z * signZ)
      e.player.velocity.z = 0
    result.colliderIds.add i
    e.t.pos += result.pushVec
