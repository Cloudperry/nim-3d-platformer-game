import std/[times, options, strformat, algorithm, math, lenientops]
import ./Containers

# Extend this logging library? It could just write the "terminal status line" in the logs normally when isatty(f) is false.
# TODO: Handle writing multiple lines between status line updates/writes correctly. Currently the logger probably breaks
# when printing a lot between status line updates.

const defaultPerfAvgDuration = initDuration(milliseconds = 250)

## A logger that writes log lines while keeping a live "status line" at the bottom of the
## terminal, and tracks rolling update/draw/frame time buffers for performance stats.
type Logger* = object
  file*: File
  perfAvgDuration*: Duration = defaultPerfAvgDuration
  updateTimes, drawTimes, frameTimes: CircularBuffer[1000, Duration]
  timeSinceLastLog: Duration = initDuration()
  lastLogI: int = 0
  lastStatusLineContent: string = ""

var globalLogger*: Logger

proc clearLine(f: var File) =
  f.write "\x1b[2K"

proc initLogger*(file: File, perfAvgDuration = defaultPerfAvgDuration): Logger =
  result = Logger(file: file)
  result.perfAvgDuration = perfAvgDuration

proc initGlobalLogger*(file: File, perfAvgDuration = defaultPerfAvgDuration) =
  ## Initializes the shared globalLogger used throughout the program.
  globalLogger = initLogger(file, perfAvgDuration)

proc writeTerminalStatusLine*(
    l: var Logger = globalLogger, msg: Option[string] = string.none
) =
  ## Rewrites the terminal's status line in place. Without a message it just redraws the
  ## last status line content (e.g. after printing a normal log line over it).
  l.file.write '\r'
  l.file.clearLine()

  let msg = if msg.isSome: msg.get else: l.lastStatusLineContent
  l.file.write msg

  l.file.flushFile()

proc log*(l: var Logger = globalLogger, msg: string) =
  ## Writes a normal log line above the status line, then redraws the status line.
  l.file.clearLine()
  l.file.write '\r'
  l.file.writeLine msg
  l.writeTerminalStatusLine()

type PerfStats* = object
  avgFrame*, avgUpdate*, avgDraw*: Duration
  minFrame*, maxFrame*: Duration
  bufferDuration*: Duration

proc getStatsForRange*(l: Logger = globalLogger, startI, endI: Natural): PerfStats =
  ## Aggregates the buffered update/draw/frame times in the given index range into averages
  ## plus the 5th/95th percentile frame times. Zero-valued (unfilled) samples are skipped.
  var count = 0
  var frameTimes: seq[Duration]
  var updateSum, drawSum, frameTimeSum = initDuration()

  for time in l.updateTimes.range(startI, endI):
    if time != initDuration():
      updateSum += time
  for time in l.drawTimes.range(startI, endI):
    if time != initDuration():
      drawSum += time
  for time in l.frameTimes.range(startI, endI):
    if time != initDuration():
      frameTimeSum += time
      frameTimes.add time
      count += 1
  sort(frameTimes)

  result.avgUpdate = updateSum div count
  result.avgDraw = drawSum div count
  result.avgFrame = frameTimeSum div count
  result.minFrame = frameTimes[round((count - 1) * 0.05).int]
  result.maxFrame = frameTimes[round((count - 1) * 0.95).int]
  result.bufferDuration = frameTimeSum

proc logPerf*(update, draw, frame: Duration, logger: var Logger = globalLogger) =
  ## Records one frame's update/draw/frame durations and, once perfAvgDuration has elapsed,
  ## updates the status line with averaged timing and FPS stats.
  logger.updateTimes.push update
  logger.drawTimes.push draw
  logger.frameTimes.push frame
  logger.timeSinceLastLog += frame

  if logger.timeSinceLastLog >= logger.perfAvgDuration:
    let stats = logger.getStatsForRange(logger.lastLogI, logger.frameTimes.i)
    let (updateAvg, drawAvg) =
      (inMicroseconds(stats.avgUpdate), inMicroseconds(stats.avgDraw))
    let fpsAvg =
      inNanoseconds(initDuration(seconds = 1)) / inNanoseconds(stats.avgFrame)
    let (minTime, maxTime) =
      (inMicroseconds(stats.minFrame), inMicroseconds(stats.maxFrame))

    logger.timeSinceLastLog = initDuration()
    logger.lastLogI = logger.frameTimes.i

    logger.writeTerminalStatusLine fmt"Update: {updateAvg} μs, Draw: {drawAvg} μs, FPS: {fpsAvg:.1f}, 5% Min/max frametimes: {minTime}/{maxTime} μs".some
