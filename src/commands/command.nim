from options import Option, some

from arg_limits import ArgLimit
from executions import Execution
from ../flag import CliValue, Flag

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
  flags: seq[Flag]

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

proc addFlag[T: CliValue](
    c: Command,
    output: var T,
    default: T = default(T),
    name: string,
    aliases: seq[string],
    shorthand: char = '_',
    help: string,
) =
  discard
