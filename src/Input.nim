import std/[tables, streams, strformat, times]
import pkg/[glm, flatty]
import ./Containers

type
  ActionKind = enum
    BoolAction
    FloatAction
    Vector2Action

  BoolActionFn = proc(active: bool)
  FloatActionFn = proc(value: float)
  Vec2ActionFn = proc(value: Vec2f)
  ActionInputs = object
    case kind*: ActionKind
    of BoolAction:
      boolVal*: bool
    of FloatAction:
      floatVal*: float
    of Vector2Action:
      vec2Val*: Vec2f

  Action = object
    runOnlyWhenNonZero: bool
    case kind*: ActionKind
    of BoolAction:
      boolFn: BoolActionFn
    of FloatAction:
      floatFn: FloatActionFn
    of Vector2Action:
      vec2Fn: Vec2ActionFn

  # TODO: Add input contexts that can be switched to have different keybinds available (e.g. menu, in-game)
  Actions*[T: enum] = Table[T, Action]
  RecordedAction*[T: enum] = object
    tickN*: uint64
    inputs*: ActionInputs
    actionName*: T
  ReplayBuffer*[T: enum] = CircularBuffer[1024, RecordedAction[T]]

proc `==`*(a1, a2: ActionInputs): bool =
  return (a1.kind == a2.kind and a1.kind == BoolAction and a1.boolVal == a2.boolVal) or
    (a1.kind == a2.kind and a1.kind == FloatAction and a1.floatVal == a2.floatVal) or
    (a1.kind == a2.kind and a1.kind == Vector2Action and a1.vec2Val == a2.vec2Val)

proc initReplayBuffer[T: enum](
    actionNames: typedesc[T]
): array[512, RecordedAction[T]] =
  result.default

proc wrapInput[T](val: T): ActionInputs =
  when T is bool:
    result = ActionInputs(kind: BoolAction, boolVal: val)
  elif T is float:
    result = ActionInputs(kind: FloatAction, floatVal: val)
  elif T is Vec2f:
    result = ActionInputs(kind: Vector2Action, vec2Val: val)
  else:
    {.error: "Unsupported input value type".}

proc run(action: Action, i: ActionInputs) =
  case action.kind
  of BoolAction:
    if not action.runOnlyWhenNonZero or i.boolVal != bool.default:
      action.boolFn(i.boolVal)
  of FloatAction:
    if not action.runOnlyWhenNonZero or i.floatVal != float.default:
      action.floatFn(i.floatVal)
  of Vector2Action:
    if not action.runOnlyWhenNonZero or i.vec2Val != Vec2f.default:
      action.vec2Fn(i.vec2Val)

proc run[T: enum](actions: Actions[T], actionName: T, i: ActionInputs) =
  actions[actionName].run(i)

proc initBoolAction*(fn: BoolActionFn, runOnlyWhenNonZero = true): Action =
  Action(kind: BoolAction, boolFn: fn, runOnlyWhenNonZero: runOnlyWhenNonZero)

proc initFloatAction*(fn: FloatActionFn, runOnlyWhenNonZero = true): Action =
  Action(kind: FloatAction, floatFn: fn, runOnlyWhenNonZero: runOnlyWhenNonZero)

proc initVector2Action*(fn: Vec2ActionFn, runOnlyWhenNonZero = true): Action =
  Action(kind: Vector2Action, vec2Fn: fn, runOnlyWhenNonZero: runOnlyWhenNonZero)

type InputsToActions*[A: enum, I] = Table[I, A]

proc addRecordingInputReader*[A, I: enum, T](
    iToA: InputsToActions[A, I],
    actions: Actions[A],
    reader: proc(inputName: I): T,
    replayBuffer: var ReplayBuffer[A],
    tickN: uint64,
    recordingEnabled = false,
): bool =
  for inputName, actionName in iToA.pairs:
    if actionName in actions:
      let input = reader(inputName).wrapInput()
      actions.run(actionName, input)
      if recordingEnabled:
        replayBuffer.push RecordedAction[A](
          actionName: actionName, inputs: input, tickN: tickN
        )
        if replayBuffer.i == 0:
          return true
  return false

proc writeFile*[A](buffer: ReplayBuffer[A], startTime: DateTime) =
  var replayBufBytes: string
  replayBufBytes.toFlatty(buffer)

  let date = startTime.format("yyyy-M-d-h-m-s")
  let f = open(fmt"{date}.{$A}.replay", fmAppend)
  f.write(replayBufBytes)
  f.close()

type ReplayPlayer*[A] = object
  replayStream*: FileStream
  replayBuf*: ReplayBuffer[A]

proc initReplayPlayer*[A](filename: string): ReplayPlayer[A] =
  ReplayPlayer[A](replayStream: newFileStream(filename, fmRead))

proc cleanup*[A](rp: var ReplayPlayer[A]) =
  rp.replayStream.close()

proc play*[A](rp: var ReplayPlayer[A], actions: Actions[A], tickN: uint64) =
  if rp.replayStream.atEnd():
    return
  
  var recAction = rp.replayBuf[rp.replayBuf.i]
  if rp.replayBuf == ReplayBuffer[A].default or tickN > recAction.tickN:
    let replayBufBytes = rp.replayStream.readStr(sizeof ReplayBuffer[A])
    rp.replayBuf = replayBufBytes.fromFlatty(ReplayBuffer[A])
    rp.replayBuf.i = 0

  while recAction.tickN <= tickN:
    recAction = rp.replayBuf[rp.replayBuf.i]
    if recAction.tickN == tickN:
      let action = actions[recAction.actionName]
      action.run(recAction.inputs)
      if rp.replayBuf.i < 1023:
        rp.replayBuf.i += 1
      else:
        break

when isMainModule:
  proc testAction(active: bool) =
    if active:
      echo "test ON"
    else:
      echo "test OFF"

  let test = initBoolAction testAction
  for value in [true, true, false, false, true]:
    test.boolFn(value)
