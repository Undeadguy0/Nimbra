import nimbra
import results
import options
import parseutils

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
    if parseFloat(arg, val) == 0:
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

  let execRes = mainCmd.tryExecute()
  if execRes.isErr:
    echo "Error: " & execRes.error.msg
