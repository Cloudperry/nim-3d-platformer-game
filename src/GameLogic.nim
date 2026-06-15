import std/[os, options, math, monotimes, tables, times]
import pkg/[glm, confutils]
import ./[SceneLogic, Input, TestScenes]

type
  ## All configurable game/renderer settings. Parsed from the command line via confutils
  ## and serialized alongside replays so playback uses the same settings as recording.
  Config* = object # Game settings
    movementMode* {.
      name: "movementMode",
      defaultValue: Walking,
      desc: "Movement mode (Flying = flying camera, Walking = FPS game controls)"
    .}: MovementMode
    mouseSensitivity* {.
      name: "mouseSensitivity", defaultValue: 2.0, desc: "Mouse sensitivity"
    .}: float
    recordInputs* {.
      name: "recordInputs",
      defaultValue: false,
      desc: "Record a replay buffer from player inputs"
    .}: bool
    replayName* {.
      name: "replayName", defaultValue: "", desc: "Replay name to play back"
    .}: string
    # Renderer settings
    slangBinPath* {.
      name: "slangBinPath",
      defaultValue: "",
      desc: "Slang shader compiler binary path (leave empty to discover from PATH)"
    .}: string
    swapInterval* {.
      name: "swapInterval",
      defaultValue: 1,
      desc: "Controls VSync (0 = VSync off, 1 = VSync on, 2 = half-rate VSync on)"
    .}: int
    compileShadersAndQuit* {.
      name: "compileShadersAndQuit",
      defaultValue: false,
      desc: "Makes the renderer only compile shaders and then quit"
    .}: bool

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

  ## Top-level mutable game state: config, the active scene, the input/replay system and
  ## per-frame bookkeeping. Passed around as a ref so updates are shared everywhere.
  GameStateRef* = ref object # Renderer state and wrapper objects
    conf*: Config
    confStorage*: StateStorage
    scene*: Scene[ColoredVertex]
    actions*: Actions[ActionNames]
    playerI*: int
    frameCount*: uint64
    replaySystem*: ReplaySystem[ActionNames]
    startTime*: DateTime
    playingReplay* = true
    frame*: FrameState

const
  appDesc* = "Nim OpenGL FPS game"
  appName* = "NimFpsGame"

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
  ## Builds the action table mapping each ActionName to a closure that mutates game state.
  ## The same table is used for live input, recording and replay playback.
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

proc initGameState*(conf = none Config): GameStateRef =
  ## Creates and initializes the game state: loads config (from the argument or command
  ## line), sets up the replay system, loads the test scene and applies the player settings.
  # Initialize game state and load config
  result = GameStateRef()
  result.conf =
    if conf.isSome:
      conf.get
    else:
      Config.load(copyrightBanner = appDesc)
  result.startTime = now()

  # Initialize replay system and save/restore config when recording/playing a replay
  let date = result.startTime.format("yyyy-M-d-h-m-s")
  result.actions = result.makeActions()
  if result.conf.replayName.len > 0:
    result.replaySystem =
      initReplayPlayer[ActionNames](result.conf.replayName, result.actions)
    result.confStorage = initStateStorage[Config](result.conf.replayName)
    let replayName = result.conf.replayName
    # Restore config that was used when the replay was recorded
    result.conf = result.confStorage.loadState(Config)
    result.conf.recordInputs = false
    result.conf.replayName = replayName
  elif result.conf.recordInputs:
    result.replaySystem = initReplayRecorder[ActionNames](date, result.actions)
    result.confStorage = initStateStorage[Config](date)
    result.confStorage.saveState(result.conf)
  else:
    result.replaySystem = initInputSystem[ActionNames](result.actions)

  # Load scene and set player settings from config
  result.playerI = result.scene.loadTestScene()
  result.player.mode = result.conf.movementMode
  result.player.cameraOpts.sensitivity = result.conf.mouseSensitivity

proc preUpdate*(game: GameStateRef): seq[RecordedAction[ActionNames]] =
  ## Resets per-frame input, then records this frame's timing (when recording) or plays back
  ## the next replay actions (when replaying). Run before reading input and before update().
  game.player.turnVec = vec2f(0)
  game.player.moveDirection = vec3f(0)
  if game.conf.replayName.len <= 0:
    game.replaySystem.recordFrameData(
      SetDeltaTime, game.frameCount, game.frame.deltaTime, game.conf.recordInputs
    )
    game.replaySystem.recordFrameData(
      SetMonoTime, game.frameCount, game.frame.monoTime, game.conf.recordInputs
    )
  else:
    if game.playingReplay:
      let playbackResult = game.replaySystem.play(game.frameCount)
      game.playingReplay = not playbackResult.replayEnded
      return playbackResult.playedActions

  return @[]

proc update*(game: var GameStateRef) =
  ## Advances the simulation by one frame and increments the frame counter.
  game.scene.update(game.frame)
  game.frameCount += 1

proc deinit*(game: GameStateRef) =
  ## Releases game resources, flushing and closing the replay system.
  game.replaySystem.deinit()
