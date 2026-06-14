import std/[options, tables]
import pkg/[glm]
import ./[SceneTypes, PlayerController, CameraController, GlUtils]
import ./glad/gl
export SceneTypes

type
  ColoredVertex* = object
    pos*, color*, normal*: Vec3f

  # TODO: Add models with textures
  TexturedVertex* = object
    pos*, normal*: Vec3f
    uv*: Vec2f

proc getTransformMat*(t: Transform): Mat4f =
  var scaleMat, translateMat, rotateMat = mat4f(1.0)
  # Scaling
  scaleMat[0, 0] = t.scale.x
  scaleMat[1, 1] = t.scale.y
  scaleMat[2, 2] = t.scale.z

  # Rotation in X -> Y -> Z order (pitch -> yaw -> roll)
  let (cx, cy, cz) = (cos(t.rotation.x), cos(t.rotation.y), cos(t.rotation.z))
  let (sx, sy, sz) = (sin(t.rotation.x), sin(t.rotation.y), sin(t.rotation.z))
  rotateMat.row0 = vec4f(cy * cz, -cy * sz, sy, 0.0)
  rotateMat.row1 = vec4f(sx * sy * cz + cx * sz, -sx * sy * sz + cx * cz, -sx * cy, 0.0)
  rotateMat.row2 = vec4f(-cx * sy * cz + sx * sz, cx * sy * sz + sx * cz, cx * cy, 0.0)

  # Translation
  translateMat[3, 0] = t.pos.x
  translateMat[3, 1] = t.pos.y
  translateMat[3, 2] = t.pos.z
  return translateMat * rotateMat * scaleMat

proc initPlayerE*(
    t: Transform, p: PlayerData, c: CameraData, bc: BoxColliderData
): Entity =
  Entity(
    kind: PlayerController,
    t: t,
    playerData: some p,
    cameraData: some c,
    boxColliderData: some bc,
    parentIds: @[rootID],
  )

proc initBoxColliderData*(
    halfExtents: Vec3f, tags = @[LevelGeo]
): BoxColliderData =
  BoxColliderData(halfExtents: halfExtents, tags: tags)

proc initBoxColliderE*(t: Transform, bc: BoxColliderData): Entity =
  Entity(kind: BoxCollider, t: t, boxColliderData: some bc, parentIds: @[rootId])

proc posColorNorm*(pos, color, normal: Vec3f): ColoredVertex =
  ColoredVertex(pos: pos, color: color, normal: normal)

proc posUvNorm*(pos: Vec3f, uv: Vec2f, normal: Vec3f): TexturedVertex =
  TexturedVertex(pos: pos, uv: uv, normal: normal)

proc initModel*[T](
    vertices: seq[T], indices: seq[GLuint] = @[], transform = Transform()
): Model[T] =
  Model[T](vertices: vertices, indices: indices, transform: transform)

proc initScene*[T](
    models: seq[Model[T]] = @[],
    dirLight = DirectionalLight.none,
    ambientLight = Vec3f.none,
): Scene[T] =
  result = Scene[T](models: models)
  result.entities.add rootNode
  if dirLight.isSome:
    result.dirLight = dirLight.get
  if ambientLight.isSome:
    result.ambientLightColor = ambientLight.get

proc addEntity*(s: var Scene, e: Entity): int =
  if s.entities.high <= s.firstFreeEntitySlot:
    s.entities.add e
    s.firstFreeEntitySlot += 1
    s.entities[0].childIds.add EntityId(id: s.entities.high, generation: 0)
    if e.kind == BoxCollider:
      s.colliderIds.add s.entities.high

  return s.entities.high

proc updatePlayer(e: var Entity, s: Scene, frame: FrameState) =
  let player = e.player
  # Camera rotation
  e.doCameraRotation(player.turnVec.x, player.turnVec.y, e.player.cameraOpts)
  # Player movement
  case player.mode
  of Flying:
    e.doFlyingCameraMovement(player.cameraOpts, frame.deltaTime)
  of Walking:
    e.doWalkingPlayerMovement(s, frame.deltaTime, frame.monoTime)

const components: Table[EntityKind, set[EntityKind]] = {
  BoxCollider: {BoxCollider},
  Camera: {Camera},
  Player: {Player},
  PlayerController: {BoxCollider, Camera, Player},
  Root: {Root},
  Base: {Base},
}.toTable
proc update*(s: var Scene, frame: FrameState) =
  for e in s.entities.mitems:
    let entityComponents = components[e.kind]
    for component in entityComponents:
      case component
      of Player:
        e.updatePlayer(s, frame)
      of Root, Base, BoxCollider, Camera, EntityKind.PlayerController:
        discard
