import pkg/glm
import ./[SceneTypes, Shapes, SceneLogic, CameraController, GlUtils]

const shapeColor = vec3f(1.0'f32, 1.0'f32, 1.0'f32)

proc loadTestScene*(scene: var Scene): int =
  let
    ground = makeBox(vec3f(40.0, 0.5, 40.0), shapeColor)
    wall = makeBox(vec3f(40.0, 7, 1.0), shapeColor)
    cube = makeBox(vec3f(0.5), shapeColor)
    pyramid = makePyramid(0.5'f32, shapeColor)
    sphere = makeSphere(0.5, 100, 100, shapeColor)
    groundModel = initModel(
      ground.vertices,
      ground.indices,
      transform = Transform(pos: vec3f(0, -2, 0), scale: vec3f(1, 1, 1)),
    )
    wallModel = initModel(
      wall.vertices,
      wall.indices,
      transform = Transform(pos: vec3f(0, 1.5, -39), scale: vec3f(1, 1, 1)),
    )
    groundModelLowerLv = initModel(
      ground.vertices,
      ground.indices,
      transform = Transform(pos: vec3f(0, -5, 40), scale: vec3f(1, 1, 1)),
    )
    roofModel = initModel(
      ground.vertices,
      ground.indices,
      transform = Transform(pos: vec3f(0, 5, 0), scale: vec3f(1, 1, 1)),
    )
    cubeModel = initModel(
      cube.vertices,
      cube.indices,
      transform = Transform(pos: vec3f(0, 0, -2), scale: vec3f(1, 1, 1)),
    )
    pyramidModel = initModel(
      pyramid.vertices,
      pyramid.indices,
      transform = Transform(pos: vec3f(-2, 0, -2), scale: vec3f(1, 1, 1)),
    )
    sphereModel = initModel(
      sphere.vertices,
      sphere.indices,
      transform = Transform(pos: vec3f(2, 0, -2), scale: vec3f(1, 1, 1)),
    )
  scene = initScene(
    @[
      groundModel, wallModel, groundModelLowerLv, roofModel, cubeModel, pyramidModel,
      sphereModel,
    ],
    DirectionalLight(
      direction: vec3f(-5, -5, -3).normalize(), color: vec3f(0.7, 0.35, 0.25)
    ).some,
    vec3f(0.1).some,
  )
  discard scene.addEntity initBoxColliderE(
    Transform(pos: vec3f(0.0, -2.0, 0.0)),
    BoxColliderData(halfExtents: vec3f(40, 0.5, 40), tags: @[Ground]),
  )
  discard scene.addEntity initBoxColliderE(
    Transform(pos: vec3f(0.0, -5.0, 40.0)),
    BoxColliderData(halfExtents: vec3f(40, 0.5, 40), tags: @[Ground]),
  )
  discard scene.addEntity initBoxColliderE(
    Transform(pos: vec3f(0.0, 1.5, -39.0)),
    BoxColliderData(halfExtents: vec3f(40, 7, 1), tags: @[LevelGeo]),
  )

  # Set camera options to defaults. Mouse sensitivity is fast on a gaming mouse, but might be too slow for a normal mouse.
  var cam = initPerspectiveCamera(80, 150 / 100, 0.1, 100)
  let collider = BoxColliderData(halfExtents: vec3f(0.25, 2.0, 0.25), tags: @[LevelGeo])
  var playerE = initPlayerE(Transform(pos: vec3f(0, 1, 0)), PlayerData(), cam, collider)

  playerE.updateTransform()
  playerE.player.cameraOpts = FpCameraOptions()

  return scene.addEntity playerE

proc loadTestSceneLights*(pointLights: var ShaderDataBufferRef[seq[PointLight]]) =
  pointLights.add PointLight(
    position: vec3f(3, 0, 3),
    color: vec3f(0.8, 0.4, 0),
    constTerm: 1,
    linearFalloff: 0.5,
    expFalloff: 1 / 20,
  )
  pointLights.add PointLight(
    position: vec3f(-3, 0, 3),
    color: vec3f(0, 0.5, 0.7),
    constTerm: 1,
    linearFalloff: 0.5,
    expFalloff: 1 / 20,
  )
  pointLights.add PointLight(
    position: vec3f(0, 0, -5),
    color: vec3f(0.4, 0.4, 0.4),
    constTerm: 1,
    linearFalloff: 0.5,
    expFalloff: 1 / 20,
  )
