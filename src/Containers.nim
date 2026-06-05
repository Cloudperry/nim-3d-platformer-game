type CircularBuffer*[N: Natural, T] = object
  data*: array[N, T]
  i*: Natural = 0 # TODO: Rename this to something less confusing

proc `[]`*[N, T](cb: CircularBuffer[N, T], i: int): T =
  cb.data[i]

proc push*[N, T](b: var CircularBuffer[N, T], v: T) =
  b.data[b.i] = v
  b.i += 1
  b.i = b.i mod b.data.len

iterator range*[N, T](b: CircularBuffer[N, T], iStart, iEnd: Natural): T =
  var i = iStart
  while true:
    yield b.data[i]
    if i == iEnd:
      break

    i += 1
    i = i mod b.data.len
