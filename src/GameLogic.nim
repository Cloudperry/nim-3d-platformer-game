#[import
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

  GameState* = object
    # Renderer state and wrapper objects
    scene*: Scene[ColoredVertex]
    playerI*: int
    frameCount*: uint64
    replaySystem*: ReplaySystem[ActionNames]
    startTime*: DateTime
    playingReplay* = true
    # TODO: Move these inside the player entity as these settings only affect how the player controller behaves
    mouseSensitivity*: float
    mode*: MovementMode

var game*: GameState

# These templates are used as aliases for long expressions throughout this file
template cam*(): untyped =
  game.scene.entities[state.playerI].camera

template player*(): untyped =
  game.scene.entities[state.playerI].player

template playerE*(): untyped =
  game.scene.entities[state.playerI]

template scene*(): untyped =
  game.scene

let actions*: Actions[ActionNames] = {
  MoveFwd: initBoolAction(
    proc(pressed: bool) =
      player.moveDirection.z -= 1
  ),
  MoveBack: initBoolAction(
    proc(pressed: bool) =
      player.moveDirection.z += 1
  ),
  MoveLeft: initBoolAction(
    proc(pressed: bool) =
      player.moveDirection.x -= 1
  ),
  MoveRight: initBoolAction(
    proc(pressed: bool) =
      player.moveDirection.x += 1
  ),
  Jump: initBoolAction(
    proc(pressed: bool) =
      player.moveDirection.y += 1
  ),
  FlyDown: initBoolAction(
    proc(pressed: bool) =
      player.moveDirection.y -= 1
  ),
  TurnCamera: initVector2Action(
    proc(turn: Vec2f) =
      player.turnVec = turn
  ),
  SetDeltaTime: initFloatAction(
    proc(dt: float) =
      frame.deltaTime = dt,
    runOnlyWhenNonZero = false,
  ),
  SetMonoTime: initMonoTimeAction(
    proc(monoTime: MonoTime) =
      frame.monoTime = monoTime,
    runOnlyWhenNonZero = false,
  ),
}.toTable

proc initGame(win: Window, mode: MovementMode mouseSensitivity: float, conf: GameConfig) GameState =
  result.startTime = now()

  let date = result.startTime.format("yyyy-M-d-h-m-s")

  result.playerI = result.scene.loadTestScene()
  player.mode = mode
  player.cameraOpts.sensitivity = mouseSensitivity

proc update(win: Window) =
  player.turnVec = vec2f(0)
  player.moveDirection = vec3f(0)
  if state.conf.replayName.len <= 0:
    state.replaySystem.recordFrameData(
      SetDeltaTime, state.frameCount, frame.deltaTime, state.conf.recordInputs
    )
    state.replaySystem.recordFrameData(
      SetMonoTime, state.frameCount, frame.monoTime, state.conf.recordInputs
    )

    # Mouse input
    state.replaySystem.addRecordingInputReader(
      axisActions,
      proc(a: AxisInputs): Vec2f =
        win.getAxis(a),
      state.frameCount,
      frame.deltaTime,
      state.conf.recordInputs,
    )

    # Keyboard input
    state.replaySystem.addRecordingInputReader(
      buttonActions,
      proc(k: Key): bool =
        win.isKeyDown(k),
      state.frameCount,
      frame.deltaTime,
      state.conf.recordInputs,
    )
  else:
    if state.playingReplay:
      state.playingReplay = state.replaySystem.play(state.frameCount)

  scene.update(frame, player.cameraOpts)

proc uninit() =
  state.replaySystem.cleanup()]#
