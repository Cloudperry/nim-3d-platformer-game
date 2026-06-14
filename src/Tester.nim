import
  std/[
    os,
    strformat,
    options,
    math,
    monotimes,
    importutils,
    tables,
    times,
    private/ospaths2,
  ]
import pkg/[confutils]
import ./[GameLogic, SceneTypes, SceneLogic, Input]

type
  TesterCliCmd* = enum
    makeTest
    runTest

  TesterConf* = object # Subcommands.
    case cmd* {.command.}: TesterCliCmd
    of makeTest:
      replayName* {.
        desc:
          "Replay path to make a test from. Doesn't include the replay file extension.",
        name: "replayName"
      .}: string
    of runTest:
      testName* {.
        desc:
          "Test path to run. Doesn't include any file extensions used in the test/replay data files.",
        name: "testName"
      .}: string

type Test = object
  replayName: string
  initialState: Scene[ColoredVertex]
  endState: Scene[ColoredVertex]

type TestPerf = object
  duration: Duration
  frames: int

proc getReplayPlaybackConfig(replayName: string): Config =
  Config(replayName: replayName, recordInputs: false)

proc makeTestFromReplay(replayName: string): Test =
  result.replayName = replayName
  let conf = getReplayPlaybackConfig(replayName)
  var game = initGameState(some conf)
  result.initialState = game.scene

  while game.playingReplay:
    game.preUpdate()
    game.update()
  result.endState = game.scene
  game.deinit()

proc makeTestCli(replayName: string) =
  stdout.write "Enter a name for saving the test data: "
  let name = stdin.readLine()
  doAssert name.len > 0, "You nust enter a name to save the test"
  let testPath = "testData" / name
  let replayFilename = ActionNames.getReplayFilename(replayName)
  let configFilename = Config.getDataBlobFilename(replayName)
  let newReplayFilename = ActionNames.getReplayFilename(testPath)
  let newConfigFilename = Config.getDataBlobFilename(testPath)
  moveFile(replayFilename, newReplayFilename)
  moveFile(configFilename, newConfigFilename)

  var test = makeTestFromReplay(testPath)
  echo fmt"Test data created from replay {replayName}. Replay and config moved to {newReplayFilename} and {newConfigFilename}."
  let testStorage = initStateStorage[Test](testPath)
  testStorage.saveState(test)

proc runTest(t: Test): bool =
  let conf = getReplayPlaybackConfig(t.replayName)
  var game = initGameState(some conf)
  game.scene = t.initialState

  while game.playingReplay:
    game.preUpdate()
    game.update()

  return game.scene == t.endState

proc runTest(testName: string): bool =
  let testPath = "testData" / testName
  let testStorage = initStateStorage[Test](testPath)
  let test = testStorage.loadState(Test)
  return runTest(test)

when isMainModule:
  let conf = TesterConf.load()
  case conf.cmd
  of makeTest:
    makeTestCli(conf.replayName)
  of runTest:
    echo runTest(conf.testName)
