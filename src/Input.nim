import std/[tables, streams, strformat, times, monotimes]
import pkg/[glm, flatty]
import ./[Containers, Logger]

const replayBufSize = 1024

type
  ActionKind = enum
    BoolAction
    FloatAction
    Vector2Action
    MonoTimeAction

  BoolActionFn = proc(active: bool)
  FloatActionFn = proc(value: float)
  Vec2ActionFn = proc(value: Vec2f)
  MonoTimeActionFn = proc(value: MonoTime)
  ActionInputs = object
    case kind*: ActionKind
    of BoolAction:
      boolVal*: bool
    of FloatAction:
      floatVal*: float
    of Vector2Action:
      vec2Val*: Vec2f
    of MonoTimeAction:
      monoTimeVal*: MonoTime

  Action = object
    runOnlyWhenNonZero: bool
    case kind*: ActionKind
    of BoolAction:
      boolFn: BoolActionFn
    of FloatAction:
      floatFn: FloatActionFn
    of Vector2Action:
      vec2Fn: Vec2ActionFn
    of MonoTimeAction:
      monoTimeFn: MonoTimeActionFn

  # TODO: Add input contexts that can be switched to have different keybinds available (e.g. menu, in-game)
  Actions*[A: enum] = Table[A, Action]
  RecordedAction*[A: enum] = object
    tickN*: uint64
    inputs*: ActionInputs
    actionName*: A

  ReplaySystemMode = enum
    InputOnly
    Player
    Recorder

  ReplayBuffer*[A: enum] = CircularBuffer[replayBufSize, RecordedAction[A]]
  ReplaySystem*[A] = object
    buf*: ReplayBuffer[A]
    actions: Actions[A]
    replayStream: FileStream
    case mode: ReplaySystemMode
    of Recorder, InputOnly:
      discard
    of Player:
      lastPlayedI: int = -1

proc getReplayFilename[A: enum](actionNames: typedesc[A], replayName: string): string =
  fmt"{replayName}.{$actionNames}.replay"

proc initReplayRecorder*[A](replayName: string, actions: Actions[A]): ReplaySystem[A] =
  let filename = A.getReplayFilename(replayName)
  return ReplaySystem[A](
    mode: Recorder, replayStream: newFileStream(filename, fmAppend), actions: actions
  )

proc initInputSystem*[A](actions: Actions[A]): ReplaySystem[A] =
  ReplaySystem[A](mode: InputOnly, actions: actions)

proc `==`*[A](r1, r2: ReplaySystem[A]): bool =
  r1.mode == r2.mode and r1.buf == r2.buf and r1.replayStream == r2.replayStream
    # NOTE: Doesn't compare actions

proc writeFile[A](rs: var ReplaySystem[A]) =
  if rs.buf.i != 0:
    for i in rs.buf.i ..< replayBufSize:
      rs.buf.data[i] = RecordedAction[A].default
  var replayBufBytes: string
  replayBufBytes.toFlatty(rs.buf)
  rs.replayStream.write(replayBufBytes)

proc recordActionAndFlushToFile[A](
    rs: var ReplaySystem[A], action: sink RecordedAction[A]
) =
  rs.buf.push action
  if rs.buf.i == 0:
    rs.writeFile()

proc cleanup*[A](rs: var ReplaySystem[A]) =
  if rs.mode == Recorder and rs != ReplaySystem[A].default and rs.buf.i != 0:
    rs.writeFile()
  rs.replayStream.close()

proc `==`*(a1, a2: ActionInputs): bool =
  return
    (a1.kind == a2.kind and a1.kind == BoolAction and a1.boolVal == a2.boolVal) or
    (a1.kind == a2.kind and a1.kind == FloatAction and a1.floatVal == a2.floatVal) or
    (a1.kind == a2.kind and a1.kind == Vector2Action and a1.vec2Val == a2.vec2Val) or (
      a1.kind == a2.kind and a1.kind == MonoTimeAction and
      a1.monoTimeVal == a2.monoTimeVal
    )

proc wrapInput[T](val: T): ActionInputs =
  when T is bool:
    result = ActionInputs(kind: BoolAction, boolVal: val)
  elif T is float:
    result = ActionInputs(kind: FloatAction, floatVal: val)
  elif T is Vec2f:
    result = ActionInputs(kind: Vector2Action, vec2Val: val)
  elif T is MonoTime:
    result = ActionInputs(kind: MonoTimeAction, monoTimeVal: val)
  else:
    {.error: "Unsupported input value type".}

proc run(action: Action, i: ActionInputs): bool =
  case action.kind
  of BoolAction:
    if not action.runOnlyWhenNonZero or i.boolVal != bool.default:
      action.boolFn(i.boolVal)
      return true
  of FloatAction:
    if not action.runOnlyWhenNonZero or i.floatVal != float.default:
      action.floatFn(i.floatVal)
      return true
  of Vector2Action:
    if not action.runOnlyWhenNonZero or i.vec2Val != Vec2f.default:
      action.vec2Fn(i.vec2Val)
      return true
  of MonoTimeAction:
    if not action.runOnlyWhenNonZero or i.monoTimeVal != MonoTime.default:
      action.monoTimeFn(i.monoTimeVal)
      return true
  return false

proc run[A: enum](actions: Actions[A], actionName: A, i: ActionInputs): bool =
  actions[actionName].run(i)

proc initBoolAction*(fn: BoolActionFn, runOnlyWhenNonZero = true): Action =
  Action(kind: BoolAction, boolFn: fn, runOnlyWhenNonZero: runOnlyWhenNonZero)

proc initFloatAction*(fn: FloatActionFn, runOnlyWhenNonZero = true): Action =
  Action(kind: FloatAction, floatFn: fn, runOnlyWhenNonZero: runOnlyWhenNonZero)

proc initVector2Action*(fn: Vec2ActionFn, runOnlyWhenNonZero = true): Action =
  Action(kind: Vector2Action, vec2Fn: fn, runOnlyWhenNonZero: runOnlyWhenNonZero)

proc initMonoTimeAction*(fn: MonoTimeActionFn, runOnlyWhenNonZero = true): Action =
  Action(kind: MonoTimeAction, monoTimeFn: fn, runOnlyWhenNonZero: runOnlyWhenNonZero)

type InputsToActions*[A: enum, I] = Table[I, A]

proc addRecordingInputReader*[A, I: enum, T](
    rs: var ReplaySystem[A],
    inputsToActions: InputsToActions[A, I],
    reader: proc(inputName: I): T,
    tickN: uint64,
    deltaTime: float,
    recordingEnabled: bool,
) =
  for inputName, actionName in inputsToActions.pairs:
    if actionName in rs.actions:
      let input = reader(inputName).wrapInput()
      let actionExecuted = rs.actions.run(actionName, input)
      if recordingEnabled and actionExecuted:
        rs.recordActionAndFlushToFile RecordedAction[A](
          actionName: actionName, inputs: input, tickN: tickN
        )

proc recordFrameData*[A, T](
    rs: var ReplaySystem[A],
    setterName: A,
    tickN: uint64,
    data: T,
    recordingEnabled: bool,
) =
  if recordingEnabled:
    let input = wrapInput(data)
    rs.recordActionAndFlushToFile RecordedAction[A](
      actionName: setterName, inputs: input, tickN: tickN
    )

proc initReplayPlayer*[A](replayName: string, actions: Actions[A]): ReplaySystem[A] =
  let filename = A.getReplayFilename(replayName)
  result = ReplaySystem[A](
    mode: Player, replayStream: newFileStream(filename, fmRead), actions: actions
  )
  doAssert not result.replayStream.isNil, fmt"Could not open replay file: {filename}"

proc play*[A](rs: var ReplaySystem[A], tickN: uint64): bool =
  result = true
    # This function returns true while the replay is being played back and false when the replay has ended

  var i = max(0, rs.lastPlayedI + 1)
    # Skip past actions that were already played during previous ticks 
  while true:
    let newBufferNeeded =
      rs.buf == ReplayBuffer[A].default or tickN > rs.buf.data[replayBufSize - 1].tickN or
      tickN == rs.buf.data[replayBufSize - 1].tickN and
      rs.lastPlayedI >= rs.buf.data.high
    # Make sure the buffer is filled with new data when needed
    if newBufferNeeded:
      if rs.replayStream.atEnd():
        return false # End of buffer
      # The size of flatty's serialized objects may not always match their size in memory, but in this case the sizes match
      let replayBufBytes = rs.replayStream.readStr(sizeof ReplayBuffer[A])
      rs.buf = replayBufBytes.fromFlatty(ReplayBuffer[A])
      i = 0
      rs.lastPlayedI = -1

    # Read and play back action from replay
    let recordedAction = rs.buf.data[i]
    if recordedAction == RecordedAction[A].default:
      return false # End of buffer
    elif recordedAction.tickN > tickN:
      break # Buffer data is newer than current tick
    elif recordedAction.tickN == tickN:
      # Execute action for current tick
      discard rs.actions[recordedAction.actionName].run(recordedAction.inputs)

    rs.lastPlayedI = i
    i += 1
