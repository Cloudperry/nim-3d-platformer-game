import std/[os, tables, strformat]
import std/monotimes
import unittest2
import pkg/glm

import ../src/[Input, GameLogic]
import ./SharedOptions

proc makeNoopActions(): Actions[ActionNames] =
  {
    MoveFwd: initBoolAction(
      proc(pressed: bool) =
        discard
    ),
    MoveBack: initBoolAction(
      proc(pressed: bool) =
        discard
    ),
    MoveLeft: initBoolAction(
      proc(pressed: bool) =
        discard
    ),
    MoveRight: initBoolAction(
      proc(pressed: bool) =
        discard
    ),
    Jump: initBoolAction(
      proc(pressed: bool) =
        discard
    ),
    FlyDown: initBoolAction(
      proc(pressed: bool) =
        discard
    ),
    TurnCamera: initVector2Action(
      proc(turn: Vec2f) =
        discard
    ),
    SetDeltaTime: initFloatAction(
      proc(dt: float) =
        discard,
      runOnlyWhenNonZero = false,
    ),
    SetMonoTime: initMonoTimeAction(
      proc(monoTime: MonoTime) =
        discard,
      runOnlyWhenNonZero = false,
    ),
  }.toTable

proc getReplayPath(testName: string): string =
  "testData" / testName

proc compareReplays(replayName1, replayName2: string): bool =
  var
    rp1 = initReplayPlayer(replayName1, makeNoopActions())
    rp2 = initReplayPlayer(replayName2, makeNoopActions())

  while true:
    let (readBuf1, readBuf2) = (rp1.readNewBuf(), rp2.readNewBuf())
    if rp1.buf != rp2.buf or readBuf1 != readBuf2:
      # Buffer sizes or contents don't match
      return false
    elif readBuf1 == false and readBuf2 == false:
      # Both replays ended at the same time with no mismatches
      return true

proc rerecordReplay(
    testName: string
): tuple[originalReplayName, rerecordedReplayName, rerecordedFilename: string] =
  let
    replayPath = getReplayPath(testName)
    rerecordedReplayPath = fmt"{replayPath}-copy"
    rerecordedFilename = ActionNames.getReplayFilename(rerecordedReplayPath)

  var player = initReplayPlayer[ActionNames](replayPath, makeNoopActions())
  var recorder =
    initReplayRecorder[ActionNames](rerecordedReplayPath, makeNoopActions())

  var tickN: uint64 = 0
  while true:
    let playback = player.play(tickN)
    for playedAction in playback.playedActions:
      recorder.recordActionAndFlushToFile(playedAction)
    if playback.replayEnded:
      break
    inc tickN

  recorder.deinit()
  player.deinit()
  return (replayPath, rerecordedReplayPath, rerecordedFilename)

suite "Replay rerecord tests":
  for testName in replayTestNames:
    test testName:
      let (originalReplayName, rerecordedReplayName, rerecordedReplayFile) =
        rerecordReplay(testName)
      check compareReplays(originalReplayName, rerecordedReplayName)
      removeFile(rerecordedReplayFile)
