## Приложение-фикстура для tests/test_exit_codes.nim. Не тест.
## Fixture app for tests/test_exit_codes.nim. Not a test.

import std/options
import nimbra

var n = 0
let
  root = newCommand("demo", help = "demo application")
  boom = newCommand("boom", help = "fail with code 3")
  code = newCommand("code", help = "exit with code 4")
  need = newCommand("need", help = "needs a flag")
  fine = newCommand("fine", help = "print fine")
root.version = "1.2.3"
root.epilog = "Run `demo <command> --help` for details."
boom.setRun proc(args: seq[string]) =
  raise newCliError("preset missing", 3)
code.setRun proc(args: seq[string]): int =
  4
fine.setRun proc(args: seq[string]) =
  echo "fine"
need.addFlag("n", n, short = some('n'), required = true)
root.add boom
root.add code
root.add need
root.add fine
root.executeOrQuit(prefix = "demo: error: ")
