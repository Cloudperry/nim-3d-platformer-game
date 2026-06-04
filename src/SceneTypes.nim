import std/[strformat, options, lenientops, monotimes, intsets]
import std/times except `getTime`
import ./glad/gl
import pkg/glm
import ./[GlUtils, Logger]

const degToRad* = PI / 180
type
  Transform* = object
    pos*: Vec3f
    scale*: Vec3f = vec3f(1.0, 1.0, 1.0)
    rotation*: Vec3f

  ProjectionKind* = enum
    Orthographic
    Perspective

  FpCameraOptions* = object
    # Pitch/yaw scaling to match Source engine. In this engine,
    # transforms use radian rotations so Source engine constants need to be scaled.
    pitchScale*: float = 0.022 * degToRad
    yawScale*: float = 0.022 * degToRad
    sensitivity*: float = 2
    moveSpeed*: float = 9
    # TODO: Focal length sensitivity scaling for intuitive feeling sensitivity while scoping/changing FOV

  CameraData* = object
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

  Model*[T] = object
    transform*: Transform
    vertices*: seq[T]
    indices*: seq[GLuint]
      # Indices can be left empty and it means the model has a raw triangle vertex list

  DirectionalLight* = object
    direction*: Vec3f # This should always be normalized
    color*: Vec3f

  Scene*[T] = object
    models*: seq[Model[T]]
    entities*: seq[Entity]
    firstFreeEntitySlot*: int
    player*: PlayerData
    colliderIds*: seq[int]
    dirLight*: DirectionalLight
    ambientLightColor*: Vec3f

  EntityId* = object
    id*: int
    generation*: uint8

  EntityKind* = enum
    Root
    Base
    Player
    Camera
    BoxCollider
    PlayerController

  Entity* = object
    kind*: EntityKind
    t*: Transform
    # Parent/child data could be just one table in Scene that holds information about all entities
    parentIds*: seq[EntityId]
    childIds*: seq[EntityId]
    playerData*: Option[PlayerData]
    cameraData*: Option[CameraData]
    boxColliderData*: Option[BoxColliderData]
    deleted*: bool
    generation*: int

  ColliderTags* = enum
    LevelGeo
    Ground
    Ignored

  BoxColliderData* = object
    halfExtents*: Vec3f
    tags*: set[ColliderTags] = {LevelGeo}

  CollisionResult* = object
    pushVec*: Vec3f
    colliderIds*: seq[int]

  MovementMode* = enum
    Flying
    Walking

  PlayerData* = object
    mode*: MovementMode
    cameraOpts*: FpCameraOptions
    jumping*: bool
    lastWallTouch*, lastGroundTouch*: MonoTime
    lastWallTouchDir*: Vec3f
    lastTouchedWallColliders*, lastJumpedWallColliders*: IntSet
    velocity*: Vec3f

  FrameState* = object
    cursorDeltaX*, cursorDeltaY*, deltaTime*: float
    moveDirection*: Vec3f
    monoTime*: MonoTime

template addSafeComponentAccessors(
    fieldName: untyped, hiddenFieldName: untyped, allowedKinds: set[EntityKind]
): untyped =
  template fieldName*(e: Entity): untyped =
    assert e.kind in allowedKinds and e.hiddenFieldName.isSome,
      "Entity of type " & $e.kind & " doesn't have the field " &
        astToStr(hiddenFieldName)
    e.hiddenFieldName.get

  template `fieldName=`*(e: var Entity, val: untyped) =
    assert e.kind in allowedKinds and e.hiddenFieldName.isSome,
      "Entity of type " & $e.kind & " doesn't have the field " &
        astToStr(hiddenFieldName)
    e.hiddenFieldName.get = val

addSafeComponentAccessors(player, playerData, {PlayerController})
addSafeComponentAccessors(camera, cameraData, {PlayerController, Camera})
addSafeComponentAccessors(boxCollider, boxColliderData, {PlayerController, BoxCollider})
let rootNode* = Entity(kind: Root)
const rootId* = EntityId(id: 0, generation: 0)
