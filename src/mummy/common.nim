import std/strutils

type
  MummyError* = object of CatchableError

  HttpVersion* = enum
    Http10, Http11

  HttpHeaders* = seq[(string, string)]

  LogLevel* = enum
    DebugLevel, InfoLevel, ErrorLevel

  LogHandler* = proc(level: LogLevel, args: varargs[string]) {.gcsafe.}

proc contains*(headers: var HttpHeaders, key: string): bool =
  ## Checks if there is at least one header for the key. Not case sensitive.
  for (k, v) in headers:
    if cmpIgnoreCase(k, key) == 0:
      return true

proc `[]`*(headers: var HttpHeaders, key: string): string =
  ## Returns the first header value the key. Not case sensitive.
  for (k, v) in headers:
    if cmpIgnoreCase(k, key) == 0:
      return v

proc `[]=`*(headers: var HttpHeaders, key, value: string) =
  ## Adds a new header if the key is not already present. If the key is already
  ## present this overrides the first header value for the key.
  ## Not case sensitive.
  for i, (k, v) in headers:
    if cmpIgnoreCase(k, key) == 0:
      headers[i][1] = value
      return
  headers.add((key, value))

proc echoLogger*(level: LogLevel, args: varargs[string]) =
  ## This is an extremely simple logger. Works well during development.
  ## Check out the file logging example in the examples/ dir for an upgrade.
  var lineLen = 0
  for arg in args:
    lineLen += arg.len
  var line = newStringOfCap(lineLen)
  for arg in args:
    line.add(arg)
  echo line
