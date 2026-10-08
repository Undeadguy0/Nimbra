import std/options

## Иерархия ошибок CLI.
##
## Движок кидает только `ref` наследников `CliError`. Печать и `quit`
## делает `gracefulHandle`, и звать его имеет право только `executeOrQuit`.
##
## CLI error hierarchy.
##
## The engine raises only `ref` descendants of `CliError`. Printing and `quit`
## live in `gracefulHandle`, and only `executeOrQuit` may call it.

type
  CliError* = object of CatchableError
  ParsingFlagError* = object of CliError
    ## Значение в argv было, но `fromString` его не принял.
    ## A value was present in argv, but `fromString` rejected it.
    flag*: string
    raw*: string

  MissingFlagError* = object of CliError
    ## Обязательного флага в argv не было. Поля `raw` нет:
    ## пустая строка здесь значила бы «значение было пустым».
    ## A required flag was absent from argv. There is no `raw` field:
    ## an empty string would mean the value was present and empty.
    flag*: string

  CliSettingError* = object of CliError
    ## Ошибка сборки дерева, до запуска. `flag` пустой, если это не флаг.
    ## Tree setup failed, before launch. `flag` is empty when this is not a flag.
    flag*: string

  ArgCountError* = object of CliError
    ## Число позиционных не попало в `ArgLimit` выбранной команды.
    ## The positional count missed the selected command's `ArgLimit`.
    got*: uint
    min*: uint
    max*: Option[uint]

proc newParsingFlagError*(msg: string, raw = "", flag = ""): ref ParsingFlagError =
  ## `flag` обычно дописывает `onValue`: `fromString` имя флага не знает.
  ## `onValue` usually fills `flag`: `fromString` does not know the flag name.
  result = newException(ParsingFlagError, msg)
  result.raw = raw
  result.flag = flag

proc newMissingFlagError*(msg: string, flag: string): ref MissingFlagError =
  result = newException(MissingFlagError, msg)
  result.flag = flag

proc newCliSettingError*(msg: string, flag = ""): ref CliSettingError =
  result = newException(CliSettingError, msg)
  result.flag = flag

proc newArgCountError*(
    msg: string, got: uint, min: uint, max: Option[uint]
): ref ArgCountError =
  result = newException(ArgCountError, msg)
  result.got = got
  result.min = min
  result.max = max

proc raiseCli*(msg: string, flag = "") {.noreturn.} =
  ## Регистрация команд и флагов. Не печатает и не завершает процесс.
  ## Command and flag registration. Does not print and does not exit the process.
  raise newCliSettingError(msg, flag)

proc toCliError*(e: ref CliError): ref CliError =
  ## Result-хук уже вернул ошибку движка. Тот же объект уходит в `raise`.
  ## A Result hook already returned an engine error. The same object is raised.
  e

proc toCliError*(msg: string): ref CliError =
  ## Result-хук вернул текст. Структура флага при этом не появляется.
  ## A Result hook returned text. No flag fields are attached.
  newException(CliError, msg)

proc `$`*(err: ref CliError): string =
  ## Читает потомка через каст к `ref`. Копия `err[]` для текста тоже
  ## увидела бы поля, но один способ каста меньше путает с записью обратно.
  ## Reads the descendant through a cast to `ref`. Copying `err[]` would
  ## also see the fields, but one cast is less confusing when writing them back.
  if err of ParsingFlagError:
    let e = (ref ParsingFlagError)(err)
    result = "Error parsing flag --" & e.flag & " from '" & e.raw & "': " & e.msg
  elif err of MissingFlagError:
    let e = (ref MissingFlagError)(err)
    result = "Missing required flag --" & e.flag & ": " & e.msg
  elif err of CliSettingError:
    let e = (ref CliSettingError)(err)
    if e.flag.len > 0:
      result = "Error while setting up flag --" & e.flag & ": " & e.msg
    else:
      result = "Error while CLI setup: " & e.msg
  elif err of ArgCountError:
    let e = (ref ArgCountError)(err)
    result = e.msg
  else:
    result = err.msg

proc gracefulHandle*(err: ref CliError) {.noreturn.} =
  ## Граница процесса. Кроме `executeOrQuit` этот выход никому не нужен.
  ## Process boundary. Nothing but `executeOrQuit` needs this exit.
  stderr.writeLine $err
  quit 1
