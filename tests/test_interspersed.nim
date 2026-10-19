## Флаги в любом месте argv, поиск команды сквозь флаги, неизвестная команда,
## короткие флаги в ошибках, `-n=1`, отрицательные числа как позиционные.
##
## Flags anywhere in argv, command lookup through flags, unknown command,
## short flags in errors, `-n=1`, negative numbers as positionals.

import std/options
import std/sequtils
import std/strutils
import std/unittest
import results
import nimbra

suite "interspersed flags":
  test "flags after and between positionals":
    var
      dry = false
      verbose = false
      only: seq[string]
    let root = newCommand("app")
    root.addFlag("dry-run", dry, short = some('n'))
    root.addFlag("verbose", verbose, short = some('v'))
    root.addFlag("only", only)
    let after = root.parse(@["pepel", "--dry-run"])
    check dry
    check after.args == @["pepel"]
    let between = root.parse(@["a", "-v", "b", "--only", "x", "c", "--only=y"])
    check verbose
    check dry == false
    check only == @["x", "y"]
    check between.args == @["a", "b", "c"]

  test "-- ends flags after positionals too":
    var verbose = false
    let root = newCommand("app")
    root.addFlag("verbose", verbose, short = some('v'))
    let parsed = root.parse(@["a", "--", "--verbose", "-v"])
    check verbose == false
    check parsed.args == @["a", "--verbose", "-v"]
    let mixed = root.parse(@["a", "-v", "--", "b", "--"])
    check verbose
    check mixed.args == @["a", "b", "--"]

  test "required flag after positional is seen, unknown flag after positional fails":
    var count = 0
    let root = newCommand("app")
    root.addFlag("count", count, required = true)
    check root.tryExecute(@["file", "--count", "3"]).isOk
    check count == 3
    let unknown = root.tryExecute(@["--count", "1", "file", "--nope"])
    check unknown.error of ParsingFlagError
    check (ref ParsingFlagError)(unknown.error).flag == "nope"

  test "bare boolean still does not take the next token":
    var
      verbose = false
      extra = false
    let root = newCommand("app")
    root.addFlag("verbose", verbose)
    root.addFlag("extra", extra)
    let parsed = root.parse(@["--verbose", "false", "--extra"])
    check verbose
    check extra
    check parsed.args == @["false"]

suite "command lookup through flags":
  test "persistent flag before the subcommand":
    var
      verbose = false
      level = 0
      ran: seq[string]
    let
      root = newCommand("app")
      serve = newCommand("serve", aliases = @["s"])
    root.addFlag("verbose", verbose, short = some('v'), persistent = true)
    root.addFlag("level", level, short = some('l'), default = some(1), persistent = true)
    root.add serve
    serve.setRun proc(args: seq[string]) =
      ran = args
    check root.tryExecute(@["--verbose", "serve", "now"]).isOk
    check verbose
    check ran == @["now"]
    let parsed = root.parse(@["-v", "-l", "3", "s", "x"])
    check parsed.path.mapIt(it.name) == @["app", "serve"]
    check verbose
    check level == 3
    check parsed.args == @["x"]
    let attached = root.parse(@["-vl7", "serve"])
    check attached.path.mapIt(it.name) == @["app", "serve"]
    check level == 7
    let eq = root.parse(@["--level=4", "serve", "-v"])
    check eq.path.mapIt(it.name) == @["app", "serve"]
    check level == 4
    check verbose

  test "flag value equal to a command name is a value":
    var name = ""
    let
      root = newCommand("app")
      serve = newCommand("serve")
    root.addFlag("name", name, persistent = true, default = some("d"))
    root.add serve
    let parsed = root.parse(@["--name", "serve", "serve", "x"])
    check parsed.path.mapIt(it.name) == @["app", "serve"]
    check name == "serve"
    check parsed.args == @["x"]

  test "flags between nested commands":
    var verbose = false
    let
      root = newCommand("app")
      mid = newCommand("mid")
      leaf = newCommand("leaf")
    root.addFlag("verbose", verbose, persistent = true)
    root.add mid
    mid.add leaf
    let parsed = root.parse(@["mid", "--verbose", "leaf", "file"])
    check parsed.path.mapIt(it.name) == @["app", "mid", "leaf"]
    check verbose
    check parsed.args == @["file"]

  test "local parent flag before the subcommand is unknown to the subcommand":
    var port = 0
    let
      root = newCommand("app")
      sub = newCommand("sub")
    root.addFlag("port", port, default = some(1))
    root.add sub
    let failed = root.tryExecute(@["--port", "3", "sub"])
    check failed.error of ParsingFlagError
    check (ref ParsingFlagError)(failed.error).flag == "port"

  test "unknown flag stops the descent and is reported":
    let
      root = newCommand("app")
      serve = newCommand("serve")
    root.add serve
    let failed = root.tryExecute(@["--nope", "serve"])
    check failed.error of ParsingFlagError
    check (ref ParsingFlagError)(failed.error).flag == "nope"

  test "-- and the first positional stop the descent":
    var seen: seq[string]
    let
      root = newCommand("app")
      serve = newCommand("serve")
    root.add serve
    root.setRun proc(args: seq[string]) =
      seen = args
    check root.tryExecute(@["--", "serve"]).isOk
    check seen == @["serve"]
    check root.tryExecute(@["file", "serve"]).isOk
    check seen == @["file", "serve"]

suite "unknown command":
  test "parent without run handler rejects an unknown word":
    let
      root = newCommand("theme")
      list = newCommand("list", aliases = @["ls"])
      current = newCommand("current")
      setc = newCommand("set")
    root.add list
    root.add current
    root.add setc
    let failed = root.tryExecute(@["bogus", "x"])
    check failed.isErr
    check failed.error of UnknownCommandError
    let e = (ref UnknownCommandError)(failed.error)
    check e.word == "bogus"
    check e.command == "theme"
    check e.available == @["list", "current", "set"]
    check "unknown command 'bogus'" in $failed.error
    check "list, current, set" in $failed.error
    check root.tryExecute(@[]).isOk
    check root.tryExecute(@["ls"]).isOk

  test "nested parent names itself":
    let
      root = newCommand("app")
      mid = newCommand("mid")
    root.add mid
    mid.add newCommand("leaf")
    let failed = root.tryExecute(@["mid", "nope"])
    check failed.error of UnknownCommandError
    check (ref UnknownCommandError)(failed.error).command == "mid"
    check (ref UnknownCommandError)(failed.error).available == @["leaf"]

  test "parent with run handler or leaf keeps positionals":
    var seen: seq[string]
    let
      root = newCommand("app")
      leaf = newCommand("leaf")
    root.add leaf
    root.setRun proc(args: seq[string]) =
      seen = args
    check root.tryExecute(@["bogus"]).isOk
    check seen == @["bogus"]
    let plain = newCommand("plain")
    check plain.tryExecute(@["word"]).isOk

  test "unknown command does not run hooks":
    var ran = false
    let root = newCommand("app")
    root.add newCommand("sub")
    root.setPreRun proc(args: seq[string]) =
      ran = true
    check root.tryExecute(@["bogus"]).error of UnknownCommandError
    check ran == false

suite "short flags":
  test "errors name a short flag with one dash":
    var port = 0
    let root = newCommand("app")
    root.addFlag("port", port, short = some('p'), default = some(1))
    let unknown = root.tryExecute(@["-z"])
    check (ref ParsingFlagError)(unknown.error).flag == "z"
    check "-z" in $unknown.error
    check "--z" notin $unknown.error
    let long = root.tryExecute(@["--zz"])
    check "--zz" in $long.error
    let bad = root.tryExecute(@["-p", "abc"])
    check (ref ParsingFlagError)(bad.error).flag == "port"
    check "--port" in $bad.error

  test "-n=1 and cluster with equals":
    var
      port = 0
      verbose = false
    let root = newCommand("app")
    root.addFlag("port", port, short = some('p'), default = some(1))
    root.addFlag("verbose", verbose, short = some('v'))
    check root.tryExecute(@["-p=80"]).isOk
    check port == 80
    check root.tryExecute(@["-vp=81"]).isOk
    check port == 81
    check verbose
    check root.tryExecute(@["-v=false"]).isOk
    check verbose == false
    check root.tryExecute(@["-v=yes", "-p8"]).isOk
    check verbose
    check port == 8
    let bad = root.tryExecute(@["-v=maybe"])
    check (ref ParsingFlagError)(bad.error).flag == "verbose"
    check (ref ParsingFlagError)(bad.error).raw == "maybe"

suite "negative numbers":
  test "negative number is positional when its digit is not a short flag":
    var verbose = false
    let root = newCommand("app")
    root.addFlag("verbose", verbose, short = some('v'))
    let parsed = root.parse(@["1", "-2", "-v", "-3.5", "-.5", "-1e3"])
    check verbose
    check parsed.args == @["1", "-2", "-3.5", "-.5", "-1e3"]
    check root.parse(@["-4"]).args == @["-4"]

  test "registered digit short flag wins, junk stays an error":
    var
      four = false
      n = 0
    let root = newCommand("app")
    root.addFlag("four", four, short = some('4'))
    root.addFlag("n", n, default = some(1))
    let parsed = root.parse(@["-4", "x"])
    check four
    check parsed.args == @["x"]
    let junk = root.tryExecute(@["-5x"])
    check junk.error of ParsingFlagError
    check (ref ParsingFlagError)(junk.error).flag == "5"
    check root.tryExecute(@["--n", "-7"]).isOk
    check n == -7

  test "negative number stops command descent":
    var seen: seq[string]
    let root = newCommand("app")
    root.add newCommand("sub")
    root.setRun proc(args: seq[string]) =
      seen = args
    check root.tryExecute(@["-1", "sub"]).isOk
    check seen == @["-1", "sub"]
