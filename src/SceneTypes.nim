import std/[strformat, options, monotimes, intsets]
import std/times except `getTime`
import ./glad/gl
import pkg/glm
import ./[GlUtils]

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

proc `==`*(c1, c2: CameraData): bool =
  let sharedFieldsMatch =
    c1.yaw == c2.yaw and c1.pitch == c2.pitch and c1.viewMat == c2.viewMat and
    c1.projectionMat == c2.projectionMat and c1.aspectRatio == c2.aspectRatio and
    c1.nearClip == c2.nearClip and c1.farClip == c2.farClip and c1.forward == c2.forward and
    c1.right == c2.right and c1.up == c2.up

  let caseFieldsMatch =
    case c1.kind
    of Orthographic:
      c2.kind == Orthographic and c1.frustumLength == c2.frustumLength
    of Perspective:
      c2.kind == Perspective and c1.verticalFov == c2.verticalFov

  return sharedFieldsMatch and caseFieldsMatch

makeGlObjects(RaiseError, std140Alignment):
  type PointLight* = object
    position*: Vec3f
    color*: Vec3f
    constTerm*, linearFalloff*, expFalloff*: GLfloat
    padding: uint32
      # Padding to take the size (as std140) up to 48 bytes. For storing inside UBO array.
    # Point lights should have a max range as well (or alternatively a minimum intensity for the light to be considered visible)

type
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
    tags*: seq[ColliderTags] = @[LevelGeo]

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
    moveDirection*: Vec3f
    turnVec*: Vec2f

  FrameState* = object
    deltaTime*: float
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
