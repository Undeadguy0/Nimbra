import ../exceptions
from options import Option, some
from strutils import isAlphaAscii, startsWith
from arg_limits import ArgLimit
from executions import Execution
from flag import CliValue, Flag, FlagSet
from results import Result, err, ok
from os import commandLineParams
from ../convertation import fromString

type Command* = ref object
  name*: string
  argLimit: Option[ArgLimit]
  help*: string
  runImpl: Option[Execution]
  preRunImpl: Option[Execution]
  persPreRunImpl: Option[Execution]
  postRunImpl: Option[Execution]
  persPostRunImpl: Option[Execution]
  subcommands: seq[Command]
  handleExceptions*: bool
  flags: FlagSet

proc setRun*(c: Command, f: Execution) =
  c.runImpl = some(f)

proc setPreRun*(c: Command, f: Execution) =
  c.preRunImpl = some(f)

proc setPostRun*(c: Command, f: Execution) =
  c.postRunImpl = some(f)

proc setPersPreRun*(c: Command, f: Execution) =
  c.persPreRunImpl = some(f)

proc setPersPostRun*(c: Command, f: Execution) =
  c.persPostRunImpl = some(f)

proc addFlag*[T: CliValue](
    c: Command,
    name: string = "",
    aliases: seq[string],
    output: var T,
    shorthand: char = '_',
    help: string,
) {.raises: [CliSettingError].} =
  if name == "":
    raiseCli("flag must have a name")
  if shorthand != '_' and not isAlphaAscii(shorthand):
    raiseCli("short flag \'" & shorthand & "\' must be a word")

  let assignFunc = proc(r: string, flagName: string) =
    try:
      output = fromString(r)
    except ParsingFlagError as pf:
      pf.flag = flagName
      pf.gracefulHandle()

  c.flags.add(
    Flag(
      name: name,
      aliases: aliases,
      help: help,
      short:
        if shorthand != '_':
          some(shorthand)
        else:
          char.none(),
      assign: assignFunc,
    )
  )

proc execute*(c: Command) {.raises: [ref EOFError, ref IOError, ref ValueError, ref CliError].} =
  try:
    let input = commandLineParams()

    for idx in 0 .. input.len - 1:
      if not input[idx].startsWith("-"):
        discard
  except CliError as ce:
    if c.handleExceptions:
      ce.gracefulHandle()
    else:
      raise ce

  discard

proc tryExecute*(c: Command): Result[void, string] =
  try:
    c.execute()
    return ok()
  except CatchableError as ce:
    return err(ce.msg)

template parseFlagsAndArgs(targetCommand: Command, flags: FlagSet, input: seq[string]) =
  discard
