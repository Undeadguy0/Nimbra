## Приложение-фикстура для tests/test_exit_codes.nim. Не тест.
## Fixture app for tests/test_exit_codes.nim. Not a test.

import nimbra

var n = 0
let
  root = newCommand("demo")
  boom = newCommand("boom")
  code = newCommand("code")
  need = newCommand("need")
  fine = newCommand("fine")
boom.setRun proc(args: seq[string]) =
  raise newCliError("preset missing", 3)
code.setRun proc(args: seq[string]): int =
  4
fine.setRun proc(args: seq[string]) =
  echo "fine"
need.addFlag("n", n, required = true)
root.add boom
root.add code
root.add need
root.add fine
root.executeOrQuit(prefix = "demo: error: ")
