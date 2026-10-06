from strutils import `%`

type
  CliError* = object of CatchableError
  ParsingFlagError* = object of CliError
    flag*: string
    raw*: string

  CliSettingError* = object of CliError
    flag*: string

proc newCliSettingError*(msg: string, flag = ""): ref CliSettingError =
  result = new CliSettingError
  result.msg = msg
  result.flag = flag

proc raiseCli*(msg: string, flag = "") {.noreturn, raises: [CliSettingError].} =
  raise newCliSettingError(msg, flag)

proc `$`*(err: ref CliError): string =
  if err of ParsingFlagError:
    let e = ParsingFlagError(err[])
    result = "Error parsing flag --$1 from '$2': $3" % [e.flag, e.raw, e.msg]
  elif err of CliSettingError:
    let e: CliSettingError = CliSettingError(err[])
    if e.flag.len > 0:
      result = "Error while setting up flag --$1: $2" % [e.flag, e.msg]
    else:
      result = "Error while CLI setup: $1" % [e.msg]
  else:
    result = err.msg

proc gracefulHandle*(
    err: ref CliError
) {.noreturn, raises: [ref ValueError, ref IOError].} =
  stderr.writeLine $err
  quit 1
