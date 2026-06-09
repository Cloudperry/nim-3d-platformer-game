import std/[options, tables]
import pkg/[glm]
import ./[SceneTypes, PlayerController, CameraController, GlUtils, Logger]
import ./glad/gl
export SceneTypes

type
  ColoredVertex* = object
    pos*, color*, normal*: Vec3f

  # TODO: Add models with textures
  TexturedVertex* = object
    pos*, normal*: Vec3f
    uv*: Vec2f

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

proc updatePlayer(e: var Entity, s: Scene, frame: FrameState, co: FpCameraOptions) =
  let player = e.player
  # Camera rotation
  e.doCameraRotation(player.turnVec.x, player.turnVec.y, co)
  # Player movement
  case player.mode
  of Flying:
    e.doFlyingCameraMovement(
      player.cameraOpts, frame.cursorDeltaX, frame.cursorDeltaY, frame.deltaTime
    )
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
proc update*(s: var Scene, frame: FrameState, co: FpCameraOptions) =
  for e in s.entities.mitems:
    let entityComponents = components[e.kind]
    for component in entityComponents:
      case component
      of Player:
        e.updatePlayer(s, frame, co)
      of Root, Base, BoxCollider, Camera, EntityKind.PlayerController:
        discard
