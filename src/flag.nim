import options
import Tables

from results import Result
from exceptions import raiseCli

type
  CliValue* = concept x
    fromString(string) is type(x)
    argHint(type(x)) is string
  Flag* = object
    short*: Option[char]
    name*: string
    aliases*: seq[string]
    help*: string
    persistent*: bool
    assign*: proc (raw: string)
  FlagSet* = object
    flags*: seq[Flag]
    byLong*: Table[string, int]
    byShort*: Table[char, int]


proc add(s: var FlagSet, f: Flag) =
  if f.name.len == 0:
    raiseCli("flag without name")
  if f.name in s.byLong:
    raiseCli("duplicate flag: --" & f.name)
