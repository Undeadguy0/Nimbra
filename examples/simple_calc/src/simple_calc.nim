import std/parseutils
import nimbra

type
  OperationType = enum
    Add
    Min
    Mul

  BadNumberError = object of CliError

proc calc(operation {.short: 'o'.}: OperationType, args: seq[string]) =
  var accum =
    case operation
    of Add: 0.0
    of Min: 0.0
    of Mul: 1.0

  for arg in args:
    var val = 0.0
    # Число должно занять весь токен: `12abc` — ошибка, а не 12.
    # The number must take the whole token: `12abc` is an error, not 12.
    if arg.len == 0 or parseFloat(arg, val) != arg.len:
      raise newException(BadNumberError, arg & " cannot be parsed into float")
    case operation
    of Add:
      accum += val
    of Min:
      accum -= val
    of Mul:
      accum *= val

  echo $accum

when isMainModule:
  defineCommand(calc, mainCmd)
  mainCmd.argLimit = atLeast(1)

  # Ошибка CLI уходит в stderr, код выхода 1.
  # A CLI error goes to stderr, exit code 1.
  mainCmd.executeOrQuit()
