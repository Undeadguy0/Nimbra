## Разделитель у списочных флагов и пустое значение строки.
## Separator for list flags and the empty string value.

import std/options
import std/unittest
import results
import nimbra

suite "list separator":
  test "split on separator, repeats combine":
    var only: seq[string]
    let root = newCommand("app")
    root.addFlag("only", only, sep = some(','))
    check root.tryExecute(@["--only", "a,b"]).isOk
    check only == @["a", "b"]
    only.setLen 0
    check root.tryExecute(@["--only=a,b", "--only", "c", "--only=d,e"]).isOk
    check only == @["a", "b", "c", "d", "e"]

  test "empty segments are skipped, empty value adds nothing":
    var only: seq[string]
    let root = newCommand("app")
    root.addFlag("only", only, sep = some(','))
    check root.tryExecute(@["--only=a,,b,"]).isOk
    check only == @["a", "b"]
    check root.tryExecute(@["--only="]).isOk
    check only == @["a", "b"]

  test "typed elements, error names the flag and the bad segment":
    var nums: seq[int]
    let root = newCommand("app")
    root.addFlag("n", nums, short = some('n'), sep = some(','))
    check root.tryExecute(@["-n", "1,-2,3"]).isOk
    check nums == @[1, -2, 3]
    nums.setLen 0
    let bad = root.tryExecute(@["--n=1,x,3"])
    check bad.error of ParsingFlagError
    check (ref ParsingFlagError)(bad.error).flag == "n"
    check (ref ParsingFlagError)(bad.error).raw == "x"

  test "other separator, no separator keeps the whole token":
    var a, b: seq[string]
    let root = newCommand("app")
    root.addFlag("path", a, sep = some(':'))
    root.addFlag("tag", b)
    check root.tryExecute(@["--path=x:y", "--tag=p,q"]).isOk
    check a == @["x", "y"]
    check b == @["p,q"]

  test "default applies when absent, sep with default":
    var only: seq[string]
    let root = newCommand("app")
    root.addFlag("only", only, default = some(@["term"]), sep = some(','))
    check root.tryExecute(@[]).isOk
    check only == @["term"]
    only.setLen 0
    check root.tryExecute(@["--only=a,b"]).isOk
    check only == @["a", "b"]

  test "persistent list flag keeps its separator in children":
    var only: seq[string]
    let
      root = newCommand("app")
      sub = newCommand("sub")
    root.addFlag("only", only, sep = some(','), persistent = true)
    root.add sub
    check root.tryExecute(@["sub", "--only=a,b"]).isOk
    check only == @["a", "b"]

suite "explicit empty string":
  test "scalar string with default":
    var s = "x"
    let root = newCommand("app")
    root.addFlag("str", s, default = some("D"))
    check root.tryExecute(@[]).isOk
    check s == "D"
    check root.tryExecute(@["--str="]).isOk
    check s == ""
    s = "x"
    check root.tryExecute(@["--str", ""]).isOk
    check s == ""

  test "Option[string] with default":
    var host = some("keep")
    let root = newCommand("app")
    root.addFlag("host", host, default = some("localhost"))
    check root.tryExecute(@["--host="]).isOk
    check host == some("")

  test "non-string types keep default on empty raw":
    var port = 1
    let root = newCommand("app")
    root.addFlag("port", port, default = some(9))
    check root.tryExecute(@["--port="]).isOk
    check port == 9
