import std/[tables]
import pkg/[glm]

type
  ActionKind = enum
    BoolAction, FloatAction, Vector2Action
  BoolActionFn = proc (active: bool)
  FloatActionFn = proc (value: float)
  Vec2ActionFn = proc (value: Vec2f)
  Action = object
    case kind*: ActionKind
    of BoolAction:
      boolFn: BoolActionFn
    of FloatAction:
      floatFn: FloatActionFn
    else:
      vec2Fn: Vec2ActionFn
  # TODO: Add input contexts that can be switched to have different keybinds available (e.g. menu, in-game)
  InputActions[T: enum] = Table[T, Action]

proc initBoolAction(fn: BoolActionFn): Action =
  Action(kind: BoolAction, boolFn: fn)
proc initFloatAction(fn: FloatActionFn): Action =
  Action(kind: FloatAction, floatFn: fn)

when isMainModule:
  proc testAction(active: bool) =
    if active:
      echo "test ON"
    else:
      echo "test OFF"
  
  let test = initBoolAction testAction
  for value in [true, true, false, false, true]:
    test.boolFn(value)