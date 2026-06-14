import pkg/glm
import ./[SceneTypes, SceneBuilder, SceneLogic, CameraController, GlUtils]

const shapeColor = vec3f(1.0'f32, 1.0'f32, 1.0'f32)

proc loadTestScene*(scene: var Scene): int =
  scene = initScene[ColoredVertex](
    dirLight =
      DirectionalLight(
        direction: vec3f(-5, -5, -3).normalize(), color: vec3f(0.7, 0.35, 0.25)
      ).some,
    ambientLight = vec3f(0.1).some,
  )

  # Ground
  scene.addBox(
    vec3f(40.0, 0.5, 40.0),
    shapeColor,
    Transform(pos: vec3f(0, -2, 0), scale: vec3f(1.25, 1, 1)),
    tags = @[Ground],
  )
  # Wall
  scene.addBox(
    vec3f(40.0, 7, 1.0),
    shapeColor,
    Transform(pos: vec3f(0, 1.5, -39), scale: vec3f(1.25, 1, 1)),
  )
  # Lower ground
  scene.addBox(
    vec3f(40.0, 0.5, 40.0),
    shapeColor,
    Transform(pos: vec3f(0, -5, 40), scale: vec3f(1.25, 1, 1)),
    tags = @[Ground],
  )
  # Roof
  scene.addBox(
    vec3f(40.0, 0.5, 40.0), shapeColor, Transform(pos: vec3f(0, 6, 0)), tags = @[Ground]
  )
  # Cube
  scene.addBox(vec3f(0.5), shapeColor, Transform(pos: vec3f(0, 0, -2)))
  # Pyramid
  scene.addPyramid(0.5'f32, shapeColor, Transform(pos: vec3f(-2, 0, -2)))
  # Sphere
  scene.addSphere(0.5, 100, 100, shapeColor, Transform(pos: vec3f(2, 0, -2)))

  # Set camera options to defaults. Mouse sensitivity is fast on a gaming mouse, but might be too slow for a normal mouse.
  var cam = initPerspectiveCamera(80, 150 / 100, 0.1, 100)
  let collider = initBoxColliderData(halfExtents = vec3f(0.25, 2.0, 0.25))
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
