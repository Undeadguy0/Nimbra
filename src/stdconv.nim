## Разбор одного токена в значение флага.
##
## `fromString` — `proc`: многострочный шаблон с `result` концепт
## раскрывает у себя и не компилирует. Имя флага сюда не приходит.
##
## Пустой токен `parseutils` съедает как 0 символов при длине 0 — это не число.
## Переполнение оттуда приходит как `ValueError` и наружу выходит
## уже как `ParsingFlagError`.
##
## Parse one token into a flag value.
##
## `fromString` is a `proc`: a multi-line template with `result` is expanded
## at the concept check and does not compile. The flag name does not arrive here.
##
## `parseutils` consumes an empty token as 0 characters of length 0. That is
## not a number. Overflow arrives as `ValueError` and leaves as `ParsingFlagError`.

import std/strutils
from std/parseutils import parseInt, parseUInt, parseFloat
from std/net import IpAddress, parseIpAddress
from exceptions import ParsingFlagError, newParsingFlagError

type CliValue* = concept x
  ## Одно значение из одного токена. `seq` и `Option` сюда не входят:
  ## это форма записи флага, а не тип токена.
  ## One value from one token. `seq` and `Option` are not included:
  ## they are flag shapes, not token types.
  fromString(type(x), string) is type(x)

proc argHint*[T](_: typedesc[T]): string =
  ## Запасной плейсхолдер help. В концепт не входит.
  ## Fallback help placeholder. Not part of the concept.
  "value"

proc argHint*(_: typedesc[int]): string =
  "int"

proc argHint*(_: typedesc[uint]): string =
  "uint"

proc argHint*(_: typedesc[float]): string =
  "float"

proc argHint*(_: typedesc[bool]): string =
  "bool"

proc argHint*(_: typedesc[char]): string =
  "char"

proc argHint*(_: typedesc[string]): string =
  "string"

proc argHint*(_: typedesc[IpAddress]): string =
  "ip"

proc rejectNumber(msg, raw: string) {.noreturn.} =
  raise newParsingFlagError(msg, raw = raw)

proc acceptWhole(consumed: int, raw, msg: string) =
  ## Ноль съеденных символов — пустая строка, знак без цифр, мусор.
  ## Хвост вроде `12abc` не съедается целиком и тоже не число.
  ## Zero characters consumed means an empty string, a sign without digits, or junk.
  ## A tail such as `12abc` is not fully consumed and is not a number either.
  if consumed == 0 or consumed != raw.len:
    rejectNumber(msg, raw)

proc fromString*(T: typedesc[int], r: string): int =
  var n = 0
  var consumed = 0
  try:
    consumed = parseInt(r, n)
  except ValueError:
    rejectNumber("not an int", r)
  acceptWhole(consumed, r, "not an int")
  n

proc fromString*(T: typedesc[uint], r: string): uint =
  var n = 0'u
  var consumed = 0
  try:
    consumed = parseUInt(r, n)
  except ValueError:
    rejectNumber("not a uint", r)
  acceptWhole(consumed, r, "not a uint")
  n

proc fromString*(T: typedesc[float], r: string): float =
  var n = 0.0
  var consumed = 0
  try:
    consumed = parseFloat(r, n)
  except ValueError:
    rejectNumber("not a float", r)
  acceptWhole(consumed, r, "not a float")
  n

proc fromString*(T: typedesc[char], r: string): char =
  if r.len != 1:
    raise newParsingFlagError("not a char", raw = r)
  r[0]

proc fromString*(T: typedesc[string], r: string): string =
  ## Пустая строка — законное значение, не признак отсутствия флага.
  ## An empty string is a real value, not the sign that the flag was omitted.
  r

proc fromString*(T: typedesc[bool], r: string): bool =
  ## Пустую строку не принимает. Голое упоминание и отсутствие
  ## разбирает замыкание флага до этого вызова.
  ## Does not accept an empty string. A bare mention and absence are handled
  ## by the flag closure before this call.
  const
    trueWords = ["1", "true", "yes", "y", "on"]
    falseWords = ["0", "false", "no", "n", "off"]
  let word = r.toLowerAscii()
  if word in trueWords:
    true
  elif word in falseWords:
    false
  else:
    raise newParsingFlagError("not a bool", raw = r)

proc fromString*[E: enum](T: typedesc[E], r: string): E =
  try:
    parseEnum[E](r)
  except ValueError as e:
    raise newParsingFlagError("bad enum: " & e.msg, raw = r)

proc fromString*(T: typedesc[IpAddress], r: string): IpAddress =
  try:
    parseIpAddress(r)
  except ValueError as e:
    raise newParsingFlagError("bad ip: " & e.msg, raw = r)
