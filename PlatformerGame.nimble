# Package
version = "0.1.0"
author = "Roni Hokkanen"
description = "3D platformer game project"
srcDir = "src"
binDir = "bin"
namedBin["Game"] = "platformer-game"
namedBin["Tester"] = "platformer-game-tester"
backend = "c"
license = "MIT"

# Dependencies
# TODO: Pin all dependencies to specific commit or at least version to prevent supply chain attacks and to make the project more likely to compile in the future
requires "nim >= 2.2.10"
requires "confutils"
requires "flatty"
requires "https://github.com/stavenko/nim-glm#47d5f8681f3c462b37e37ebc5e7067fa5cba4d16"
requires "glfw == 3.4.0.5"
requires "https://github.com/status-im/nim-unittest2"

# Tasks
task test, "Run the replay regression tests":
  exec "nim c --hints:off -r tests/AllTests.nim"
