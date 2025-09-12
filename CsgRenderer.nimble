# Package
version = "0.1.0"
author = "Roni Hokkanen"
description = "A computer graphics project in Nim and OpenGL"
srcDir = "src"
binDir = "bin"
namedBin["Renderer"] = "nim-opengl-renderer"
backend = "c"
license = "MIT"

# Dependencies
requires "nim >= 2.3.1"
requires "cligen >= 1.9.0"
requires "opengl >= 1.2.9"
requires "https://github.com/stavenko/nim-glm#47d5f8681f3c462b37e37ebc5e7067fa5cba4d16"
requires "glfw"
