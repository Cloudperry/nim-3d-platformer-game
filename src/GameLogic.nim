import
  std/[
    os, strformat, options, math, monotimes, sequtils, importutils, sugar, tables, times
  ]
import std/times except `getTime`
import pkg/[glm, glfw, confutils, flatty]
from pkg/glfw/wrapper import `rawMouseMotionSupported`
import
  ./[
    GlUtils, Slangc, Logger, Shapes, SceneLogic, PlayerController, CameraController,
    Math, Input, TestScenes, Containers,
  ]
import ./glad/gl

type
  ActionNames* = enum
    MoveFwd
    MoveBack
    MoveLeft
    MoveRight
    Jump
    FlyDown
    TurnCamera
    SetDeltaTime
    SetMonoTime
  GameConfig* = object
    recordInputs*: bool
    replayName*: string
    mode*: MovementMode
    mouseSensitivity*: float

  GameStateRef* = ref object
    # Renderer state and wrapper objects
    scene*: Scene[ColoredVertex]
    actions*: Actions[ActionNames]
    playerI*: int
    frameCount*: uint64
    replaySystem*: ReplaySystem[ActionNames]
    startTime*: DateTime
    playingReplay* = true
    frame*: FrameState
    # TODO: Move these inside the player entity as these settings only affect how the player controller behaves
    mouseSensitivity*: float
    mode*: MovementMode
  
# These templates are used as aliases for long expressions throughout this file
template cam*(game: GameStateRef): untyped =
  game.scene.entities[game.playerI].camera

template player*(game: GameStateRef): untyped =
  game.scene.entities[game.playerI].player

template playerE*(game: GameStateRef): untyped =
  game.scene.entities[game.playerI]

template scene*(game: GameStateRef): untyped =
  game.scene

proc makeActions*(game: GameStateRef): Actions[ActionNames] = 
  return {
    MoveFwd: initBoolAction(
      proc(pressed: bool) =
        game.player.moveDirection.z -= 1
    ),
    MoveBack: initBoolAction(
      proc(pressed: bool) =
        game.player.moveDirection.z += 1
    ),
    MoveLeft: initBoolAction(
      proc(pressed: bool) =
        game.player.moveDirection.x -= 1
    ),
    MoveRight: initBoolAction(
      proc(pressed: bool) =
        game.player.moveDirection.x += 1
    ),
    Jump: initBoolAction(
      proc(pressed: bool) =
        game.player.moveDirection.y += 1
    ),
    FlyDown: initBoolAction(
      proc(pressed: bool) =
        game.player.moveDirection.y -= 1
    ),
    TurnCamera: initVector2Action(
      proc(turn: Vec2f) =
        game.player.turnVec = turn
    ),
    SetDeltaTime: initFloatAction(
      proc(dt: float) =
        game.frame.deltaTime = dt,
      runOnlyWhenNonZero = false,
    ),
    SetMonoTime: initMonoTimeAction(
      proc(monoTime: MonoTime) =
        game.frame.monoTime = monoTime,
      runOnlyWhenNonZero = false,
    ),
  }.toTable

proc initGame*(conf: GameConfig): GameStateRef =
  result = GameStateRef()
  result.startTime = now()

  result.playerI = result.scene.loadTestScene()
  result.player.mode = conf.mode
  result.player.cameraOpts.sensitivity = conf.mouseSensitivity

  let date = result.startTime.format("yyyy-M-d-h-m-s")
  result.actions = result.makeActions()
  if conf.replayName.len > 0:
    result.replaySystem = initReplayPlayer[ActionNames](conf.replayName, result.actions)
  elif conf.recordInputs:
    result.replaySystem = initReplayRecorder[ActionNames](date, result.actions)
  else:
    result.replaySystem = initInputSystem[ActionNames](result.actions)

proc preUpdate*(game: GameStateRef, conf: GameConfig) =
  game.player.turnVec = vec2f(0)
  game.player.moveDirection = vec3f(0)
  if conf.replayName.len <= 0:
    game.replaySystem.recordFrameData(
      SetDeltaTime, game.frameCount, game.frame.deltaTime, conf.recordInputs
    )
    game.replaySystem.recordFrameData(
      SetMonoTime, game.frameCount, game.frame.monoTime, conf.recordInputs
    )
  else:
    if game.playingReplay:
      game.playingReplay = game.replaySystem.play(game.frameCount)

proc update*(game: var GameStateRef) =
  game.scene.update(game.frame)
  game.frameCount += 1

proc uninit(game: GameStateRef) =
  game.replaySystem.cleanup()
