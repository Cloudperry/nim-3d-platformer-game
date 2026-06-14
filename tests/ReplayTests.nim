import unittest2

import ../src/Tester

# Replay-based regression tests. Each name corresponds to a set of data files
# under testData/ (<name>.Test.bin, <name>.Config.bin, <name>.ActionNames.replay).
# Running a test replays the recorded inputs from the saved initial state and
# checks that the resulting scene matches the saved end state.
#
# The names are hardcoded based on the current testData/ contents for now.
const replayTestNames = [
  "flyingCameraTest1",
  "jumpTest1",
  "jumpTest2",
  "walljumpParkourTest1",
  "walljumpParkourTest2",
]

suite "Replay regression tests":
  for testName in replayTestNames:
    test testName:
      check runTest(testName)
