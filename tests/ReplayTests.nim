import unittest2

import ../src/Tester
import ./SharedOptions

# Replay-based regression tests. Each name corresponds to a set of data files
# under testData/ (<name>.Test.bin, <name>.Config.bin, <name>.ActionNames.replay).
# Running a test replays the recorded inputs from the saved initial state and
# checks that the resulting scene matches the saved end state.

suite "Replay regression tests":
  for testName in replayTestNames:
    test testName:
      check runTest(testName)
