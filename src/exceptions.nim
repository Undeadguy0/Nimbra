from strutils import `%`

type
  ParsingFlagError* = object of CatchableError
    flag*: string
    raw*: string

  CliSettingError* = object of CatchableError
    flag*: string

proc newCliSettingError*(msg: string, flag = ""): ref CliSettingError =
  result = new CliSettingError
  result.msg = msg 
  result.flag = flag

proc raiseCli*(msg: string, flag = "") {.noreturn, raises: [CliSettingError].} =
  raise newCliSettingError(msg, flag)

proc gracefulHandle*(err: ref CatchableError) {.noreturn.} =
  if err of ParsingFlagError:
    let e = ParsingFlagError(err)
    stderr.writeLine "Error parsing flag --$1 from '$2': $3" % [e.flag, e.raw, e.msg]
    quit 2
  elif err of CliSettingError:
    let e = CliSettingError(err)
    if e.flag.len > 0:
      stderr.writeLine "Error while setting up flag --$1: $2" % [e.flag, e.msg]
    else:
      stderr.writeLine "Error while CLI setup: $1" % [e.msg]
    quit 1
  else:
    stderr.writeLine err.msg
    quit 1