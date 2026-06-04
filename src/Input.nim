import std/[tables]
import pkg/[glm]

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

proc initBoolAction*(fn: BoolActionFn, runOnlyWhenNonZero = true): Action =
  Action(kind: BoolAction, boolFn: fn, runOnlyWhenNonZero: runOnlyWhenNonZero)

proc initFloatAction*(fn: FloatActionFn, runOnlyWhenNonZero = true): Action =
  Action(kind: FloatAction, floatFn: fn, runOnlyWhenNonZero: runOnlyWhenNonZero)

proc initVector2Action*(fn: Vec2ActionFn, runOnlyWhenNonZero = true): Action =
  Action(kind: Vector2Action, vec2Fn: fn, runOnlyWhenNonZero: runOnlyWhenNonZero)

type InputsToActions*[A: enum, I] = Table[I, A]

proc addInputReader*[A: enum, I, T](
    iToA: InputsToActions[A, I], actions: Actions[A], reader: proc(inputName: I): T
) =
  for inputName, actionName in iToA.pairs:
    if actionName in actions:
      let input = reader(inputName).wrapInput()
      actions[actionName].run(input)

when isMainModule:
  proc testAction(active: bool) =
    if active:
      echo "test ON"
    else:
      echo "test OFF"

  let test = initBoolAction testAction
  for value in [true, true, false, false, true]:
    test.boolFn(value)
