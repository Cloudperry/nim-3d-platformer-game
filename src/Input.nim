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

  ReplayBuffer*[A: enum] = CircularBuffer[replayBufSize, RecordedAction[A]]
  ReplayRecorder*[A] = object
    buf*: ReplayBuffer[A]
    actions: Actions[A]
    replayStream: FileStream

proc initReplayRecorder*[A](filename: string, actions: Actions[A]): ReplayRecorder[A] =
  ReplayRecorder[A](replayStream: newFileStream(filename, fmAppend), actions: actions)

proc `==`*[A](r1, r2: ReplayRecorder[A]): bool =
  r1.buf == r2.buf and r1.replayStream == r2.replayStream # NOTE: Doesn't compare actions

proc writeFile(recorder: ReplayRecorder) =
  var replayBufBytes: string
  replayBufBytes.toFlatty(recorder.buf)
  recorder.replayStream.write(replayBufBytes)

proc recordActionAndFlushToFile[A](
    recorder: var ReplayRecorder[A], action: sink RecordedAction[A]
) =
  recorder.buf.push action
  if recorder.buf.i == 0:
    recorder.writeFile()

proc cleanup*[A](rr: var ReplayRecorder[A]) =
  if rr != ReplayRecorder[A].default:
    rr.writeFile()
  rr.replayStream.close()

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
    recorder: var ReplayRecorder[A],
    inputsToActions: InputsToActions[A, I],
    reader: proc(inputName: I): T,
    tickN: uint64,
    deltaTime: float,
    recordingEnabled: bool,
) =
  for inputName, actionName in inputsToActions.pairs:
    if actionName in recorder.actions:
      let input = reader(inputName).wrapInput()
      let actionExecuted = recorder.actions.run(actionName, input)
      if recordingEnabled and actionExecuted:
        recorder.recordActionAndFlushToFile RecordedAction[A](
          actionName: actionName, inputs: input, tickN: tickN
        )

proc recordFrameData*[A, T](
    recorder: var ReplayRecorder[A],
    setterName: A,
    tickN: uint64,
    data: T,
    recordingEnabled: bool,
) =
  if recordingEnabled:
    let input = wrapInput(data)
    recorder.recordActionAndFlushToFile RecordedAction[A](
      actionName: setterName, inputs: input, tickN: tickN
    )

type ReplayPlayer*[A] = object
  replayStream: FileStream
  replayBuf: ReplayBuffer[A]
  lastPlayedI: int
  actions: Actions[A]
  setDtAction: Action

proc initReplayPlayer*[A](filename: string, actions: Actions[A]): ReplayPlayer[A] =
  result =
    ReplayPlayer[A](replayStream: newFileStream(filename, fmRead), actions: actions)
  doAssert not result.replayStream.isNil, fmt"Could not open replay file: {filename}"

proc cleanup*[A](rp: ReplayPlayer[A]) =
  rp.replayStream.close()

proc play*[A](rp: var ReplayPlayer[A], tickN: uint64): bool =
  if not rp.replayStream.atEnd() and (
    rp.replayBuf == ReplayBuffer[A].default or
    tickN > rp.replayBuf.data[replayBufSize - 1].tickN
  ):
    let replayBufBytes = rp.replayStream.readStr(sizeof ReplayBuffer[A])
    rp.replayBuf = replayBufBytes.fromFlatty(ReplayBuffer[A])
    rp.lastPlayedI = 0

  for i, recordedAction in rp.replayBuf.data[rp.lastPlayedI ..< replayBufSize]:
    if recordedAction == RecordedAction[A].default or recordedAction.tickN > tickN:
      break
    elif recordedAction.tickN == tickN:
      let action = rp.actions[recordedAction.actionName]
      discard action.run(recordedAction.inputs)
      rp.lastPlayedI = i

  return true

when isMainModule:
  proc testAction(active: bool) =
    if active:
      echo "test ON"
    else:
      echo "test OFF"

  let test = initBoolAction testAction
  for value in [true, true, false, false, true]:
    test.boolFn(value)
