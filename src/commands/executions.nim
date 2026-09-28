from results import Result

type
  ExecKind* = enum
    clear
    ecxeptionable
    resultive

  Execution* = object
    case kind*: ExecKind
    of clear: clearProc: proc()
    of ecxeptionable: unsafeProc: proc()
    of resultive: resultProc: proc(): Result[void, string]

proc ClearExecution*(f: proc()): Execution =
  return Execution(kind: ExecKind.clear, clearProc: f)

proc CatchableExecution*(f: proc()): Execution =
  return Execution(kind: ExecKind.ecxeptionable, unsafeProc: f)

proc ResultiveExecution*(f: proc(): Result[void, string]): Execution =
  return Execution(kind: ExecKind.resultive, resultProc: f)
