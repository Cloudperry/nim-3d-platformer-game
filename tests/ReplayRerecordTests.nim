import std/[os, tables, strformat]
import std/sha1
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

proc getReplayActionsHash(replayName: string): string =
  var player = initReplayPlayer[ActionNames](replayName, makeNoopActions())
  defer:
    player.deinit()

  var tickN: uint64 = 0
  var replayActions: seq[RecordedAction[ActionNames]]
  while true:
    let playback = player.play(tickN)
    replayActions.add(playback.playedActions)
    if playback.replayEnded:
      break
    tickN += 1

  var hashInput =
    newStringUninit(replayActions.len * sizeof RecordedAction[ActionNames])
  for i, action in replayActions:
    let byteOffset = i * sizeof(action)
    copyMem(addr hashInput[byteOffset], unsafeAddr action, sizeof(action))
  $secureHash(hashInput)

proc rerecordReplay(
    testName: string
): tuple[originalReplayName, rerecordedReplayName, rerecordedFilename: string] =
  let
    replayPath = getReplayPath(testName)
    rerecordedReplayPath = fmt"{replayPath}.rerecorded"
    rerecordedFilename = ActionNames.getReplayFilename(rerecordedReplayPath)

  if fileExists(rerecordedFilename):
    removeFile(rerecordedFilename)

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
      defer:
        if fileExists(rerecordedReplayFile):
          removeFile(rerecordedReplayFile)
      check getReplayActionsHash(originalReplayName) ==
        getReplayActionsHash(rerecordedReplayName)
