import std/options
import std/sequtils
import std/unittest
import results
import nimbra

suite "argv parsing":
  test "root not searched by tokens, unknown word - positional":
    let root = newCommand("app")
    let parsed = root.parse(@["app", "file"])
    check parsed.path.len == 1
    check parsed.args == @["app", "file"]

  test "descend by name and alias, commands not searched further":
    let
      root = newCommand("app")
      mid = newCommand("server", aliases = @["s"])
      leaf = newCommand("start")
    root.add mid
    mid.add leaf
    let byAlias = root.parse(@["s", "start", "now"])
    check byAlias.path.mapIt(it.name) == @["app", "server", "start"]
    check byAlias.args == @["now"]
    let stopped = root.parse(@["server", "file", "start"])
    check stopped.path[^1].name == "server"
    check stopped.args == @["file", "start"]
    let skipped = root.parse(@["start"])
    check skipped.path.len == 1
    check skipped.args == @["start"]

  test "flags, clusters, negative numbers and --":
    var
      verbose = false
      extra = false
      port = 0
      count = 0
    let root = newCommand("app")
    root.addFlag("verbose", verbose, short = some('v'))
    root.addFlag("extra", extra, short = some('x'))
    root.addFlag("port", port, short = some('p'), default = some(1))
    root.addFlag("count", count, required = true)
    let parsed = root.parse(@["-vx", "-p8080", "--count", "-4", "file", "--nope"])
    check verbose
    check extra
    check port == 8080
    check count == -4
    check parsed.args == @["file", "--nope"]

  test "short flag value as separate token and -- skip":
    var port = 0
    let root = newCommand("app")
    root.addFlag("port", port, short = some('p'), required = true)
    check root.tryExecute(@["-p", "7"]).isOk
    check port == 7
    let missing = root.tryExecute(@["-p"])
    check missing.isErr
    check missing.error of ParsingFlagError
    let stopped = root.tryExecute(@["--port", "--"])
    check stopped.isErr
    check stopped.error of ParsingFlagError

  test "unknown flag and lone minus":
    var verbose = false
    let root = newCommand("app")
    root.addFlag("verbose", verbose)
    let unknown = root.tryExecute(@["--nope"])
    check unknown.isErr
    check (ref ParsingFlagError)(unknown.error).flag == "nope"
    let parsed = root.parse(@["--verbose", "-"])
    check verbose
    check parsed.args == @["-"]

  test "after first positional tail not parsed as flags":
    var verbose = false
    let root = newCommand("app")
    root.addFlag("verbose", verbose)
    let parsed = root.parse(@["file", "--verbose"])
    check verbose == false
    check parsed.args == @["file", "--verbose"]

  test "limit counted at selected command":
    let
      root = newCommand("app")
      sub = newCommand("sub")
    root.argLimit = exact(0)
    sub.argLimit = exact(2)
    root.add sub
    check root.tryExecute(@["only"]).error of ArgCountError
    let wrong = root.tryExecute(@["sub", "one"])
    check wrong.isErr
    let e = (ref ArgCountError)(wrong.error)
    check e.got == 1
    check e.min == 2
    check e.max == some(2'u)
    check root.tryExecute(@["sub", "one", "two"]).isOk

  test "constructor boundaries":
    let root = newCommand("app")
    root.argLimit = noArgs()
    check root.tryExecute(@[]).isOk
    check root.tryExecute(@["x"]).isErr
    root.argLimit = atLeast(1)
    check root.tryExecute(@["x"]).isOk
    root.argLimit = atMost(1)
    check root.tryExecute(@["x", "y"]).isErr
    root.argLimit = between(1, 2)
    check root.tryExecute(@["x", "y"]).isOk
    expect CliSettingError:
      discard between(3, 1)

  test "parse does not call hooks":
    var ran = false
    let root = newCommand("app")
    root.setRun proc(args: seq[string]) =
      ran = true
    discard root.parse(@["file"])
    check ran == false
    check root.tryExecute(@["file"]).isOk
    check ran

  test "parse does not check limit, flag error and limit do not call hooks":
    var ran = false
    var port = 0
    let root = newCommand("app")
    root.argLimit = noArgs()
    root.addFlag("port", port, required = true)
    root.setRun proc(args: seq[string]) =
      ran = true
    let parsed = root.parse(@["--port", "1", "file"])
    check parsed.args == @["file"]
    check port == 1
    check ran == false
    check root.tryExecute(@[]).error of MissingFlagError
    check ran == false
    check root.tryExecute(@["--port", "1", "file"]).error of ArgCountError
    check ran == false
    check root.tryExecute(@["--port", "2"]).isOk
    check port == 2
    check ran

  test "-- hides tail and does not count as flag mention":
    var count = 3
    let need = newCommand("app")
    need.addFlag("count", count, required = true)
    let hidden = need.tryExecute(@["--", "--count", "4"])
    check hidden.error of MissingFlagError
    check count == 3

    var verbose = false
    let plain = newCommand("app")
    plain.addFlag("verbose", verbose)
    let parsed = plain.parse(@["--", "--verbose", "-v"])
    check parsed.args == @["--verbose", "-v"]
    check verbose == false

  test "flag interrupts command descent":
    var verbose = false
    let
      root = newCommand("app")
      serve = newCommand("serve")
    root.addFlag("verbose", verbose, persistent = true)
    root.add serve
    let before = root.parse(@["--verbose", "serve"])
    check before.path.mapIt(it.name) == @["app"]
    check verbose
    check before.args == @["serve"]
    let between = root.parse(@["serve", "--verbose", "now"])
    check between.path.mapIt(it.name) == @["app", "serve"]
    check verbose
    check between.args == @["now"]

  test "bare boolean does not consume next token":
    var
      verbose = false
      extra = false
    let root = newCommand("app")
    root.addFlag("verbose", verbose, short = some('v'))
    root.addFlag("extra", extra, short = some('x'))
    let word = root.parse(@["--verbose", "false", "--extra"])
    check verbose
    check extra == false
    check word.args == @["false", "--extra"]
    let flags = root.parse(@["--verbose", "--extra"])
    check verbose
    check extra
    check flags.args.len == 0
    let eq = root.parse(@["--verbose=false", "--extra"])
    check verbose == false
    check extra
    check eq.args.len == 0
    check root.tryExecute(@["--verbose=YES"]).isOk
    check verbose
    check extra == false
    check root.tryExecute(@["--verbose="]).isOk
    check verbose == false
    let short = root.parse(@["-v", "false"])
    check verbose
    check short.args == @["false"]

  test "cluster: booleans, remainder and next token":
    var
      verbose = false
      extra = false
      port = 0
    let root = newCommand("app")
    root.addFlag("verbose", verbose, short = some('v'))
    root.addFlag("extra", extra, short = some('x'))
    root.addFlag("port", port, short = some('p'), required = true)
    let mixed = root.parse(@["-vxp15"])
    check verbose
    check extra
    check port == 15
    check mixed.args.len == 0
    let split = root.parse(@["-vp", "4"])
    check verbose
    check extra == false
    check port == 4
    let stuck = root.tryExecute(@["-p=80"])
    check stuck.error of ParsingFlagError
    check (ref ParsingFlagError)(stuck.error).flag == "port"
    check (ref ParsingFlagError)(stuck.error).raw == "=80"
    check port == 4
    let unknown = root.tryExecute(@["-xq"])
    check (ref ParsingFlagError)(unknown.error).flag == "q"
    check extra

  test "no value and value looking like flag":
    var
      port = 1
      verbose = false
    let root = newCommand("app")
    root.addFlag("port", port, short = some('p'), required = true)
    root.addFlag("verbose", verbose)
    let eof = root.tryExecute(@["--port"])
    check (ref ParsingFlagError)(eof.error).flag == "port"
    check (ref ParsingFlagError)(eof.error).raw == "--port"
    let dash = root.tryExecute(@["--port", "--"])
    check (ref ParsingFlagError)(dash.error).raw == "--port"
    let shortEof = root.tryExecute(@["-p"])
    check (ref ParsingFlagError)(shortEof.error).flag == "port"
    check (ref ParsingFlagError)(shortEof.error).raw == "-p"
    let shortDash = root.tryExecute(@["-p", "--"])
    check (ref ParsingFlagError)(shortDash.error).raw == "-p"
    check port == 1
    check verbose == false
    let looks = root.tryExecute(@["--port", "--verbose"])
    check (ref ParsingFlagError)(looks.error).flag == "port"
    check (ref ParsingFlagError)(looks.error).raw == "--verbose"
    check verbose == false
    check port == 1
    check root.tryExecute(@["--port", "-3", "--verbose"]).isOk
    check port == -3
    check verbose

  test "repeat, alias and first equals":
    var
      port = 0
      name = ""
    let root = newCommand("app")
    root.addFlag("port", port, aliases = @["p"], required = true)
    root.addFlag("name", name, required = true)
    check root.tryExecute(@["--port", "1", "--p", "2", "--name=a=b=c"]).isOk
    check port == 2
    check name == "a=b=c"
    let bad = root.tryExecute(@["--p=12abc", "--name", "z"])
    check (ref ParsingFlagError)(bad.error).flag == "port"
    check (ref ParsingFlagError)(bad.error).raw == "12abc"
    check port == 2
    check root.tryExecute(@["--name", "", "--port", "8"]).isOk
    check name == ""
    check port == 8

  test "empty token starts positional":
    var verbose = false
    let root = newCommand("app")
    root.addFlag("verbose", verbose)
    let parsed = root.parse(@["", "--verbose"])
    check verbose == false
    check parsed.args == @["", "--verbose"]

  test "unknown short flag and minus with digit":
    var n = 0
    let root = newCommand("app")
    root.addFlag("n", n, default = some(1))
    let bad = root.tryExecute(@["-z"])
    check (ref ParsingFlagError)(bad.error).flag == "z"
    check (ref ParsingFlagError)(bad.error).raw == "-z"
    let dashed = root.tryExecute(@["---"])
    check (ref ParsingFlagError)(dashed.error).flag == "-"
    check root.tryExecute(@["-4"]).error of ParsingFlagError
    let hidden = root.parse(@["--", "-4"])
    check hidden.args == @["-4"]
    check n == 1

  test "mention marks do not live between runs":
    var n = 0
    let root = newCommand("app")
    root.addFlag("n", n, required = true)
    check root.tryExecute(@["--n", "1"]).isOk
    check n == 1
    check root.tryExecute(@["--n", "2"]).isOk
    check n == 2
    check root.tryExecute(@[]).error of MissingFlagError
    check n == 2

  test "raw token reaches fromString intact":
    var
      n = 0
      f = 0.0
    let root = newCommand("app")
    root.addFlag("n", n, required = true)
    root.addFlag("f", f, default = some(1.0))
    check root.tryExecute(@["--n=1_000", "--f=.5"]).isOk
    check n == 1000
    check f == 0.5
    check root.tryExecute(@["--n=1_000", "--f="]).isOk
    check f == 1.0
    let bad = root.tryExecute(@["--n="])
    check (ref ParsingFlagError)(bad.error).flag == "n"
    check (ref ParsingFlagError)(bad.error).raw == ""
    check n == 1000

  test "flags only at selected command":
    var
      parentPort = 0
      childPort = 0
    let
      root = newCommand("app")
      sub = newCommand("sub")
    root.addFlag("parent", parentPort, default = some(1))
    root.add sub
    sub.addFlag("child", childPort, required = true)
    check root.tryExecute(@["--child", "2"]).error of ParsingFlagError
    check parentPort == 0
    check root.tryExecute(@[]).isOk
    check parentPort == 1
    check root.tryExecute(@["sub", "--parent", "3"]).error of ParsingFlagError
    check childPort == 0
    check parentPort == 1
    check root.tryExecute(@["sub", "--child", "4"]).isOk
    check childPort == 4
    check parentPort == 1

  test "limit does not count flags":
    var verbose = false
    let root = newCommand("app")
    root.argLimit = exact(1)
    root.addFlag("verbose", verbose)
    check root.tryExecute(@["--verbose", "file"]).isOk
    check verbose
    let missed = root.tryExecute(@["--verbose"])
    check missed.error of ArgCountError
    check (ref ArgCountError)(missed.error).got == 0
    check root.tryExecute(@["--verbose", "a", "b"]).error of ArgCountError

  test "command, alias and tail after --":
    var
      verbose = false
      port = 0
    let
      root = newCommand("app")
      serve = newCommand("serve", aliases = @["s"])
    root.add serve
    serve.addFlag("verbose", verbose, short = some('v'))
    serve.addFlag("port", port, aliases = @["p"], short = some('o'), required = true)
    let parsed = root.parse(@["s", "-v", "--p", "9", "--", "--verbose"])
    check parsed.path.mapIt(it.name) == @["app", "serve"]
    check verbose
    check port == 9
    check parsed.args == @["--verbose"]
    let again = root.parse(@["serve", "-o9"])
    check port == 9
    check verbose == false
    check again.args.len == 0
