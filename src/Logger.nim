import std/[os, times, options, strformat]

type
  CircularBuffer*[N: Natural, T] = object
    data*: array[N, T]
    i*: Natural = 0

proc push*[N, T](b: var CircularBuffer[N, T], v: T) =
  b.data[b.i] = v
  b.i += 1
  b.i = b.i mod b.data.len

iterator range*[N, T](b: CircularBuffer[N, T]; iStart, iEnd: Natural): T =
  var i = iStart
  while true:
    yield b.data[i]
    if i == iEnd: break

    i += 1
    i = i mod b.data.len

# Extend this logging library? It could just write the "terminal status line" in the logs normally when isatty(f) is false.
type Logger* = object
  file: File
  perfAvgDuration: Duration = initDuration(milliseconds = 250)
  updateTimes, drawTimes, frameTimes: CircularBuffer[1000, Duration]
  timeSinceLastLog: Duration = initDuration()
  lastLogI: int = 0
  lastStatusLineContent: string = ""

proc clearLine(f: var File) = f.write "\x1b[2K"

proc initLogger*(file: File, perfAvgDuration = Duration.none): Logger =
  result = Logger(file: file)
  if perfAvgDuration.isSome:
    result.perfAvgDuration = perfAvgDuration.get

proc writeTerminalStatusLine*(l: var Logger, msg: Option[string] = string.none) = 
  l.file.write '\r'
  l.file.clearLine()

  let msg = if msg.isSome:
    msg.get
  else:
    l.lastStatusLineContent
  l.file.write msg

  l.file.flushFile()

proc log*(l: var Logger, msg: string) =
  l.file.clearLine()
  l.file.write '\r'
  l.file.writeLine msg
  l.writeTerminalStatusLine()

proc logPerf*(logger: var Logger; update, draw, frame: Duration) =
  logger.updateTimes.push update
  logger.drawTimes.push draw
  logger.frameTimes.push frame
  logger.timeSinceLastLog += frame

  if logger.timeSinceLastLog >= logger.perfAvgDuration:
    var updateSum, drawSum, frameTimeSum = initDuration()
    for time in logger.updateTimes.range(logger.lastLogI, logger.updateTimes.i): updateSum += time
    for time in logger.drawTimes.range(logger.lastLogI, logger.drawTimes.i): drawSum += time

    var (frameTimeMin, frameTimeMax) = (Duration.high, Duration.low)
    var count = 0
    for time in logger.frameTimes.range(logger.lastLogI, logger.frameTimes.i): 
      frameTimeSum += time
      frameTimeMin = min(time, frameTimeMin)
      frameTimeMax = max(time, frameTimeMax)
      count += 1

    logger.timeSinceLastLog = initDuration()
    logger.lastLogI = logger.frameTimes.i

    let (updateAvg, drawAvg, minTime, maxTime) = (
      inMicroseconds(updateSum div count), inMicroseconds(drawSum div count), inMicroseconds(frameTimeMin), inMicroseconds(frameTimeMax)
    )
    let fpsAvg = initDuration(seconds = 1).inNanoseconds() / inNanoseconds(frameTimeSum div count)
    logger.writeTerminalStatusLine fmt"Update: {updateAvg} μs, Draw: {drawAvg} μs, FPS: {fpsAvg:.1f}, Min/max frametimes: {minTime}/{maxTime} μs".some
