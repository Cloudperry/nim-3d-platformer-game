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
import ./[GameLogic, Input]

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
  initialState: GameStateRef
  endState: GameStateRef

type TestPerf = object
  duration: Duration
  frames: int

proc makeTestFromReplay(replayName: string): Test =
  result.replayName = replayName
  let conf = Config(replayName: replayName, recordInputs: false)
  var game = initGameState(some conf)
  deepCopy(game, result.initialState)

  while game.playingReplay:
    game.preUpdate()
    game.update()
  deepCopy(game, result.endState)
  game.deinit()

proc makeTestCli(replayName: string) =
  var test = makeTestFromReplay(replayName)
  echo fmt"Test data created from replay {replayName}"
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
  let stateStorage = initStateStorage[Test](testPath)
  stateStorage.saveState(test)

proc runTest(t: Test): bool =
  var game = t.initialState

  while game.runningReplay:
    game.preUpdate()
    game.update()

  return game[] == t.endState[]

when isMainModule:
  let conf = TesterConf.load()
  case conf.cmd
  of makeTest:
    makeTestCli(conf.replayName)
  of runTest:
    echo runTest(conf.testName)
