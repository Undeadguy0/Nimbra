import parseutils
from commands/flag import CliValue
from exceptions import ParsingFlagError
from options import Option, some, none
from strutils import toLower
from net import IpAddress, parseIpAddress
import macros

const FALSE_ALIASES = @["", "false", "0"]


template fromString*(T: typedesc[int], r: string): int =
  result = 0
  if parseInt(r, result) == 0:
    raise new ParsingFlagError

template fromString*(T: typedesc[string], r: string): string =
  r

template fromString*(T: typedesc[uint], r: string): uint =
  result = 0
  if parseUInt(r, result) == 0:
    raise new ParsingFlagError

template fromString*(T: typedesc[float], r: string): float =
  result = 0.0
  if parseFloat(r, result) == 0:
    raise new ParsingFlagError

template fromString*(T: typedesc[char], r: string): char =
  if r.len != 1:
    raise new ParsingFlagError
  r[0]

template fromString*(T: typedesc[bool], r: string): bool = 
  r.toLower() notin FALSE_ALIASES

proc fromString*[T: CliValue](S: typedesc[seq[T]], r: string): seq[T] =
  for part in r.split(','):
    if part.len > 0:
      result.add fromString(T, part)

proc fromString*[T: CliValue](O: typedesc[Option[T]], r: string): Option[T] =
  result = none(T)
  if r.len > 0:
    result = some(fromString(T, r))


macro toEnum*(e: typed, s: string): untyped =
  let impl = e.getImpl
  let typeName = impl[0]

  result = quote do:
    case `s`
  for elem in impl[2]:
    if elem.kind == nnkEmpty:
      continue
    let field =
      if elem.kind == nnkEnumFieldDef:
        elem[0]
      else:
        elem
    result.add newTree(
      nnkOfBranch, newLit(field.strVal), newDotExpr(typeName, ident(field.strVal))
    )
  result.add newTree(
    nnkElse,
    quote do:
      raise newException(ParsingFlagError, "bad enum: " & `s`),
  )



template fromString*(E: typedesc[enum], r: string): E = E.toEnum(r)

template fromString*(I: typedesc[IpAddress], r: string) : I =
  try:
    parseIpAddress(r)
  except ValueError as ve:
    raise newException(ParsingFlagError, "bad ip: " & ve.msg)