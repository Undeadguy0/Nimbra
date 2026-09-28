type
  ParcingFlagError* = object of CatchableError
    flag*: string
    raw*: string

  CliSettingError* = object of CatchableError
    flag*: string


proc newCliSettingError*(msg: string,  flag = ""): ref CliSettingError =
  result = new CliSettingError
  result.msg = msg
  result.flag = flag

proc raiseCli*(msg: string,  flag = "") {.noreturn.} =
  raise newCliSettingError(msg, flag)
