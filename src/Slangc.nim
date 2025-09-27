import std/[os, osproc, strformat, strutils]

type
  ShaderStage* = enum
    Fragment = "fragment", Vertex = "vertex", Compute = "compute"
  TargetFormat* = enum
    Glsl = "glsl", SpirV = "spirv"
  SlangcOptions* = object
    inFile, entryPoint*, outFile*: string
    slangPath*: string = "/opt/shader-slang-bin/bin"
    target: TargetFormat
    stage: ShaderStage

proc short(s: ShaderStage): string = 
  case s
  of Fragment: "Frag"
  of Vertex: "Vert"
  of Compute: "Comp"

proc updateOutFile(o: var SlangcOptions) =
  let inputName = o.inFile.split(".")
  o.outFile = fmt"{inputName[0]}{o.stage.short()}.{o.target}"
proc fillDefaultOpts(o: var SlangcOptions) =
  if o.outFile.len == 0:
    o.updateOutFile()

proc `inFile=`*(o: var SlangcOptions, path: string) =
  o.inFile = path
  o.updateOutFile()
proc `target=`*(o: var SlangcOptions, target: TargetFormat) =
  o.target = target
  o.updateOutFile()
proc `stage=`*(o: var SlangcOptions, s: ShaderStage) =
  o.stage = s
  o.updateOutFile()

# TODO: Check if Slang is already in PATH and use it if it is
proc makeSlangCmd(o: var SlangcOptions): string =
  o.fillDefaultOpts()
  let entryPointOptArg = if o.entryPoint.len > 0:
    fmt" -entry {o.entryPoint}"
  else:
    ""
  let slangBin = o.slangPath / "slangc"
  return fmt"{slangBin} {o.inFile} -no-mangle -target {o.target} -stage {o.stage}{entryPointOptArg} -profile glsl_460 -o {o.outFile}"

proc compileShaderOrRaise*(o: var SlangcOptions): string =
  let cmdRes = o.makeSlangCmd().execCmdEx()
  if cmdRes.exitCode != 0:
    raise newException(Exception, &"Failed to compile shader {o.inFile}:\n\n{cmdRes.output}")

  return o.outFile.readFile()

if isMainModule:
  var opts = SlangcOptions(
    inFile: "/home/roni/Programming/Games/FpsTestNim/shaders/HelloTriangle.slang",
    outFile: "/home/roni/Programming/Games/FpsTestNim/shaders/HelloTriangleVert.glsl",
    stage: Vertex, entryPoint: "vertexMain", target: Glsl
  )
  echo compileShaderOrRaise(opts)
  opts = SlangcOptions(
    inFile: "/home/roni/Programming/Games/FpsTestNim/shaders/HelloTriangle.slang",
    outFile: "/home/roni/Programming/Games/FpsTestNim/shaders/HelloTriangleFrag.glsl",
    stage: Fragment, entryPoint: "fragmentMain", target: Glsl
  )
  echo compileShaderOrRaise(opts)
