import std/options
import std/unittest
import results
import nimbra

suite "flag registration":
  test "required with default and required on bool do not register":
    var
      port = 1
      verbose = false
    let root = newCommand("app")
    expect CliSettingError:
      root.addFlag("port", port, default = some(1), required = true)
    expect CliSettingError:
      root.addFlag("verbose", verbose, required = true)

  test "duplicate name, alias and short flag":
    var
      a = 0
      b = 0
    let root = newCommand("app")
    root.addFlag("port", a, aliases = @["p"], short = some('p'))
    expect CliSettingError:
      root.addFlag("port", b)
    expect CliSettingError:
      root.addFlag("other", b, aliases = @["p"])
    expect CliSettingError:
      root.addFlag("else", b, short = some('p'))

  test "empty command name and alias collision":
    let root = newCommand("app")
    expect CliSettingError:
      root.add newCommand("")
    expect CliSettingError:
      discard newCommand("server", aliases = @["server"])
    root.add newCommand("server", aliases = @["s"])
    expect CliSettingError:
      root.add newCommand("status", aliases = @["s"])
    expect CliSettingError:
      discard newCommand("app", aliases = @[""])
    expect CliSettingError:
      discard newCommand("app", aliases = @["a", "a"])

  test "empty flag name, empty alias and duplicate flag alias":
    var n = 0
    let root = newCommand("app")
    expect CliSettingError:
      root.addFlag("", n)
    expect CliSettingError:
      root.addFlag("port", n, aliases = @[""])
    expect CliSettingError:
      root.addFlag("port", n, aliases = @["port"])
    expect CliSettingError:
      root.addFlag("port", n, aliases = @["p", "p"])

suite "value policy":
  test "required int: empty raw - parse error, absent - MissingFlagError":
    var port = 5
    let root = newCommand("app")
    root.addFlag("port", port, aliases = @["p"], required = true)
    let missing = root.tryExecute(@[])
    check missing.isErr
    check missing.error of MissingFlagError
    check (ref MissingFlagError)(missing.error).flag == "port"
    check port == 5
    let empty = root.tryExecute(@["--port="])
    check empty.isErr
    check empty.error of ParsingFlagError
    check (ref ParsingFlagError)(empty.error).flag == "port"
    check (ref ParsingFlagError)(empty.error).raw == ""
    check port == 5
    let emptyToken = root.tryExecute(@["--p", ""])
    check emptyToken.error of ParsingFlagError
    check (ref ParsingFlagError)(emptyToken.error).raw == ""
    check port == 5
    let bad = root.tryExecute(@["--p", "12abc"])
    check bad.isErr
    let parsed = (ref ParsingFlagError)(bad.error)
    check parsed.flag == "port"
    check parsed.raw == "12abc"
    check port == 5
    check root.tryExecute(@["--port", "-3"]).isOk
    check port == -3

  test "explicit default covers absent and empty raw, but not garbage":
    var port = 1
    let root = newCommand("app")
    root.addFlag("port", port, default = some(9))
    check root.tryExecute(@[]).isOk
    check port == 9
    check root.tryExecute(@["--port="]).isOk
    check port == 9
    check root.tryExecute(@["--port", "4"]).isOk
    check port == 4
    check root.tryExecute(@["--port", "12abc"]).isErr
    check port == 4

  test "without required and without default, absent does not touch variable":
    var n = 5
    let root = newCommand("app")
    root.addFlag("n", n)
    check root.tryExecute(@[]).isOk
    check n == 5
    check root.tryExecute(@["--n="]).isErr
    check n == 5
    check root.tryExecute(@["--n", ""]).isErr
    check n == 5

  test "required string can be empty":
    var name = "preset"
    let root = newCommand("app")
    root.addFlag("name", name, required = true)
    check root.tryExecute(@["--name="]).isOk
    check name == ""
    name = "preset"
    check root.tryExecute(@[]).error of MissingFlagError
    check name == "preset"

  test "bool: no flag - false, bare mention - true":
    var verbose = true
    let root = newCommand("app")
    root.addFlag("verbose", verbose, short = some('v'))
    check root.tryExecute(@[]).isOk
    check verbose == false
    check root.tryExecute(@["--verbose"]).isOk
    check verbose
    check root.tryExecute(@["-v"]).isOk
    check verbose
    check root.tryExecute(@["--verbose=false"]).isOk
    check verbose == false
    check root.tryExecute(@["--verbose="]).isOk
    check verbose == false
    # repeat run without flag writes false again; seen mark does not stick
    check root.tryExecute(@["--verbose"]).isOk
    check verbose
    check root.tryExecute(@[]).isOk
    check verbose == false

  test "explicit bool default":
    var verbose = false
    let root = newCommand("app")
    root.addFlag("verbose", verbose, default = some(true))
    check root.tryExecute(@[]).isOk
    check verbose
    check root.tryExecute(@["--verbose="]).isOk
    check verbose
    check root.tryExecute(@["--verbose=no"]).isOk
    check verbose == false

  test "seq repeat appends one token, absent substitutes list default":
    var tags = @["keep"]
    let root = newCommand("app")
    root.addFlag("tag", tags, default = some(@["d"]))
    check root.tryExecute(@[]).isOk
    check tags == @["d"]
    check root.tryExecute(@["--tag", "a", "--tag", "b"]).isOk
    check tags == @["d", "a", "b"]
    check root.tryExecute(@["--tag=a,b"]).isOk
    check tags == @["d", "a", "b", "a,b"]
    check root.tryExecute(@["--tag="]).isOk
    check tags[^1] == ""

  test "required seq and empty int element":
    var
      names: seq[string]
      nums: seq[int]
    let root = newCommand("app")
    root.addFlag("name", names, required = true)
    root.addFlag("n", nums)
    check root.tryExecute(@[]).error of MissingFlagError
    check root.tryExecute(@["--name", "a"]).isOk
    check names == @["a"]
    check root.tryExecute(@["--name", "a", "--n", "1", "--n", "-2"]).isOk
    check nums == @[1, -2]
    check root.tryExecute(@["--name", "a", "--n="]).isErr
    check nums == @[1, -2]
    check root.tryExecute(@["--name", ""]).isOk
    check names[^1] == ""

  test "Option: absent clears initial some":
    var host = some("keep")
    let root = newCommand("app")
    root.addFlag("host", host, default = some("localhost"))
    check root.tryExecute(@[]).isOk
    check host == some("localhost")
    check root.tryExecute(@["--host="]).isOk
    check host == some("localhost")
    check root.tryExecute(@["--host", "box"]).isOk
    check host == some("box")

  test "Option without default becomes none":
    var host = some("keep")
    let root = newCommand("app")
    root.addFlag("host", host)
    check root.tryExecute(@[]).isOk
    check host.isNone
    check root.tryExecute(@["--host", "box"]).isOk
    check host == some("box")
    check root.tryExecute(@["--host", "a", "--host", "b"]).isOk
    check host == some("b")
    check root.tryExecute(@["--host="]).isOk
    check host == some("")

  test "required Option and empty int do not hide":
    var
      need = some("keep")
      port = some(1)
    let root = newCommand("app")
    root.addFlag("need", need, required = true)
    root.addFlag("port", port, default = some(9))
    let missing = root.tryExecute(@[])
    check missing.error of MissingFlagError
    check (ref MissingFlagError)(missing.error).flag == "need"
    check need == some("keep")
    check root.tryExecute(@["--need", "box"]).isOk
    check need == some("box")
    check root.tryExecute(@["--need", "box", "--port="]).isOk
    check port == some(9)
    let bad = root.tryExecute(@["--need", "box", "--port", "12abc"])
    check bad.error of ParsingFlagError
    check (ref ParsingFlagError)(bad.error).flag == "port"
    check (ref ParsingFlagError)(bad.error).raw == "12abc"
    check port == some(9)
    var bare = some(4)
    let other = newCommand("app")
    other.addFlag("n", bare)
    check other.tryExecute(@["--n="]).error of ParsingFlagError
    check bare == some(4)

  test "seq without default remains as was":
    var tags = @["keep"]
    let root = newCommand("app")
    root.addFlag("tag", tags)
    check root.tryExecute(@[]).isOk
    check tags == @["keep"]
    check root.tryExecute(@["--tag", "a"]).isOk
    check tags == @["keep", "a"]

suite "persistent":
  test "parent flag visible to children and writes to same variable":
    var verbose = false
    let
      root = newCommand("app")
      mid = newCommand("mid")
      leaf = newCommand("leaf")
    root.addFlag("verbose", verbose, persistent = true)
    root.add mid
    mid.add leaf
    check root.tryExecute(@["mid", "leaf", "--verbose"]).isOk
    check verbose
    check root.tryExecute(@["mid", "leaf"]).isOk
    check verbose == false

  test "already built subtree receives persistent on add":
    var verbose = false
    let
      root = newCommand("app")
      mid = newCommand("mid")
      leaf = newCommand("leaf")
    mid.add leaf
    root.addFlag("verbose", verbose, persistent = true)
    root.add mid
    check root.tryExecute(@["mid", "leaf", "--verbose"]).isOk
    check verbose

  test "local flag does not flow down, own duplicate - registration error":
    var
      port = 1
      other = 0
      verbose = false
      childVerbose = false
    let
      root = newCommand("app")
      sub = newCommand("sub")
    root.addFlag("port", port, default = some(1))
    root.add sub
    check root.tryExecute(@["sub", "--port", "2"]).error of ParsingFlagError
    root.addFlag("verbose", verbose, persistent = true)
    expect CliSettingError:
      sub.addFlag("verbose", childVerbose)
    check root.tryExecute(@["sub", "--verbose"]).isOk
    check verbose
    check not childVerbose
    expect CliSettingError:
      root.addFlag("extra", other, persistent = true)
      sub.addFlag("extra", other)

  test "persistent reaches grandchild and writes once":
    var
      verbose = false
      tags: seq[string]
    let
      root = newCommand("app")
      mid = newCommand("mid")
      leaf = newCommand("leaf")
    root.add mid
    mid.add leaf
    root.addFlag("verbose", verbose, persistent = true)
    root.addFlag("tag", tags, persistent = true)
    check root.tryExecute(@["mid", "leaf", "--verbose", "--tag", "a"]).isOk
    check verbose
    check tags == @["a"]
    tags.setLen 0
    check root.tryExecute(@["--tag", "b"]).isOk
    check tags == @["b"]
    check root.tryExecute(@["mid", "leaf"]).isOk
    check verbose == false

  test "local flag not visible to parent or grandchild":
    var port = 0
    let
      root = newCommand("app")
      mid = newCommand("mid")
      leaf = newCommand("leaf")
    root.add mid
    mid.add leaf
    mid.addFlag("port", port, required = true)
    check root.tryExecute(@["--port", "1"]).error of ParsingFlagError
    check root.tryExecute(@["mid", "--port", "2"]).isOk
    check port == 2
    check root.tryExecute(@["mid", "leaf", "--port", "3"]).error of ParsingFlagError
    check port == 2

  test "persistent refusal does not leave flag on half tree":
    var
      quiet = false
      verbose = false
      childVerbose = false
      leafVerbose = false
    let
      root = newCommand("app")
      mid = newCommand("mid")
      leaf = newCommand("leaf")
      blocked = newCommand("blocked")
    leaf.addFlag("verbose", leafVerbose)
    root.add mid
    mid.add leaf
    expect CliSettingError:
      root.addFlag("verbose", verbose, persistent = true)
    check root.tryExecute(@["--verbose"]).error of ParsingFlagError
    check root.tryExecute(@["mid", "--verbose"]).error of ParsingFlagError
    check root.tryExecute(@["mid", "leaf", "--verbose"]).isOk
    check leafVerbose
    check not verbose

    root.addFlag("quiet", quiet, persistent = true)
    root.addFlag("other", verbose, persistent = true)
    blocked.addFlag("quiet", childVerbose)
    expect CliSettingError:
      root.add blocked
    let notChild = root.parse(@["blocked"])
    check notChild.path.len == 1
    check notChild.args == @["blocked"]
    check blocked.tryExecute(@["--other"]).error of ParsingFlagError
    check blocked.tryExecute(@["--quiet"]).isOk
    check childVerbose
