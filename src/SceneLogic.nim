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
  ## Builds the model-to-world matrix from a Transform, applying scale, then XYZ rotation
  ## (pitch -> yaw -> roll), then translation.
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
  ## Creates a player controller entity bundling the player, camera and box collider
  ## components, parented to the scene root.
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
  ## Creates box collider data with the given half-extents, defaulting to level geometry tags.
  BoxColliderData(halfExtents: halfExtents, tags: tags)

proc initBoxColliderE*(t: Transform, bc: BoxColliderData): Entity =
  ## Creates a standalone box collider entity parented to the scene root.
  Entity(kind: BoxCollider, t: t, boxColliderData: some bc, parentIds: @[rootId])

proc posColorNorm*(pos, color, normal: Vec3f): ColoredVertex =
  ColoredVertex(pos: pos, color: color, normal: normal)

proc posUvNorm*(pos: Vec3f, uv: Vec2f, normal: Vec3f): TexturedVertex =
  TexturedVertex(pos: pos, uv: uv, normal: normal)

proc initModel*[T](
    vertices: seq[T], indices: seq[GLuint] = @[], transform = Transform()
): Model[T] =
  ## Creates a renderable model. An empty indices list means the vertices are a raw
  ## triangle list instead of an indexed mesh.
  Model[T](vertices: vertices, indices: indices, transform: transform)

proc initScene*[T](
    models: seq[Model[T]] = @[],
    dirLight = DirectionalLight.none,
    ambientLight = Vec3f.none,
): Scene[T] =
  ## Creates a scene seeded with the root entity and optional directional/ambient lighting.
  result = Scene[T](models: models)
  result.entities.add rootNode
  if dirLight.isSome:
    result.dirLight = dirLight.get
  if ambientLight.isSome:
    result.ambientLightColor = ambientLight.get

proc addEntity*(s: var Scene, e: Entity): int =
  ## Adds an entity, registers it as a child of the root and tracks it in colliderIds if it
  ## is a box collider. Returns the index of the added entity.
  if s.entities.high <= s.firstFreeEntitySlot:
    s.entities.add e
    s.firstFreeEntitySlot += 1
    s.entities[0].childIds.add EntityId(id: s.entities.high, generation: 0)
    if e.kind == BoxCollider:
      s.colliderIds.add s.entities.high

  return s.entities.high

proc updatePlayer(e: var Entity, s: Scene, frame: FrameState) =
  ## Updates a player for one frame: camera rotation, then movement for the current mode
  ## (flying camera or walking FPS controls).
  let player = e.player
  # Camera rotation
  e.doCameraRotation(player.turnVec.x, player.turnVec.y, e.player.cameraOpts)
  # Player movement
  case player.mode
  of Flying:
    e.doFlyingCameraMovement(player.cameraOpts, frame.deltaTime)
  of Walking:
    e.doWalkingPlayerMovement(s, frame.deltaTime, frame.monoTime)

# Maps each entity kind to the set of component kinds it has, so update() can dispatch to
# the right per-component logic (megastruct pattern).
const components: Table[EntityKind, set[EntityKind]] = {
  BoxCollider: {BoxCollider},
  Camera: {Camera},
  Player: {Player},
  PlayerController: {BoxCollider, Camera, Player},
  Root: {Root},
  Base: {Base},
}.toTable
proc update*(s: var Scene, frame: FrameState) =
  ## Advances the whole scene by one frame, updating each entity's components.
  for e in s.entities.mitems:
    let entityComponents = components[e.kind]
    for component in entityComponents:
      case component
      of Player:
        e.updatePlayer(s, frame)
      of Root, Base, BoxCollider, Camera, EntityKind.PlayerController:
        discard
