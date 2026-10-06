import options
import Tables

from results import Result
from ../exceptions import raiseCli, CliSettingError

type
  CliValue* = concept x
    fromString(type(x), string) is type(x)
    argHint(type(x)) is string
  Flag* = object
    short*: Option[char]
    name*: string
    aliases*: seq[string]
    help*: string
    isBoolean: bool
    assign*: proc(raw: string, flagName: string)

  FlagSet* = object
    flags*: seq[Flag]
    byLong*: Table[string, int]
    byShort*: Table[char, int]

proc add*(s: var FlagSet, f: Flag) {.raises: [CliSettingError].} =
  if f.name.len == 0:
    raiseCli("flag without name")
  if f.name in s.byLong:
    raiseCli("duplicate flag: --" & f.name)

  for a in f.aliases:
    if a in s.byLong:
      raiseCli("duplicate flag: --" & a)

  if f.short.isSome:
    if f.short.get in s.byShort:
      raiseCli("duplicate flag: -" & f.short.get)

  let commIdx = s.flags.len
  s.flags.add f

  s.byLong[f.name] = commIdx
  for a in f.aliases:
    s.byLong[a] = commIdx

  if f.short.isSome:
    s.byShort[f.short.get] = commIdx

proc get*[K: string | char](s: FlagSet, key: K): Option[Flag] =
  when K is char:
    try:
      return some(s.byShort[key])
    except KeyError:
      return none
  else:
    try:
      return some(s.byLong[key])
    except KeyError:
      return none
