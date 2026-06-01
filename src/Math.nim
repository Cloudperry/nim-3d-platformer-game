import std/[math]
import pkg/[glm]
import ./SceneTypes

proc getTransformMat*(t: Transform): Mat4f =
  var scaleMat, translateMat, rotateMat = mat4f(1.0)
  # Scaling
  scaleMat[0, 0] = t.scale.x
  scaleMat[1, 1] = t.scale.y
  scaleMat[2, 2] = t.scale.z

  # Rotation in X -> Y -> Z order (pitch -> yaw -> roll)
  let (cx, cy, cz) = (cos(t.rotation.x), cos(t.rotation.y), cos(t.rotation.z))
  let (sx, sy, sz) = (sin(t.rotation.x), sin(t.rotation.y), sin(t.rotation.z))
  rotateMat.row0 = vec4f( cy * cz                 , -cy * sz                , sy       , 0.0 )
  rotateMat.row1 = vec4f( sx * sy * cz + cx * sz  , -sx * sy * sz + cx * cz , -sx * cy , 0.0 )
  rotateMat.row2 = vec4f( -cx * sy * cz + sx * sz , cx * sy * sz + sx * cz  , cx * cy  , 0.0 )

  # Translation
  translateMat[3, 0] = t.pos.x
  translateMat[3, 1] = t.pos.y
  translateMat[3, 2] = t.pos.z
  return translateMat * rotateMat * scaleMat