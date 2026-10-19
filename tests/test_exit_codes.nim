## Коды выхода, int-обработчики, ValueError из пользовательских парсеров,
## порядок ошибок в post-хуках.
##
## Exit codes, int handlers, ValueError from user parsers, error order in
## post hooks.

import std/options
import std/os
import std/osproc
import std/streams
import std/strutils
import std/unittest
import results
import nimbra

const root = currentSourcePath().parentDir.parentDir

type Level = distinct int

proc fromString(T: typedesc[Level], r: string): Level =
  if r == "bad":
    raise newException(ValueError, "no such level")
  Level(r.len)

suite "exit code on errors":
  test "defaults: usage errors 2, others 1":
    check exitCode(newParsingFlagError("x")) == 2
    check exitCode(newMissingFlagError("x", "f")) == 2
    check exitCode(newUnknownCommandError("a", "app", @["b"])) == 2
    check exitCode(newArgCountError("x", 1, 0, none(uint))) == 2
    check exitCode(newCliSettingError("x")) == 1
    check exitCode(newCliError("x")) == 1
    check exitCode(toCliError("text")) == 1

  test "explicit code wins":
    check exitCode(newCliError("x", 3)) == 3
    let e = newParsingFlagError("x")
    e.code = 7
    check exitCode(e) == 7

  test "code survives tryExecute and a subclass":
    type MyErr = object of CliError
    let root = newCommand("app")
    root.setRun proc(args: seq[string]) =
      let e = newException(MyErr, "mine")
      e.code = 9
      raise e
    let r = root.tryExecute(@[])
    check r.isErr
    check exitCode(r.error) == 9
    check exitCode(newException(MyErr, "plain")) == 1

suite "int handlers":
  test "executeCode returns the handler result":
    let root = newCommand("app")
    root.setRun proc(args: seq[string]): int =
      args.len + 10
    check root.executeCode(@["a", "b"]) == 12
    check root.tryExecuteCode(@[]).get == 10

  test "void handler and no handler give 0":
    let root = newCommand("app")
    check root.executeCode(@[]) == 0
    root.setRun proc(args: seq[string]) = discard
    check root.executeCode(@[]) == 0

  test "setRun replaces the other kind":
    var log: seq[string]
    let root = newCommand("app")
    root.setRun proc(args: seq[string]) =
      log.add "void"
    root.setRun proc(args: seq[string]): int =
      log.add "int"
      5
    check root.executeCode(@[]) == 5
    root.setRun proc(args: seq[string]) =
      log.add "void2"
    check root.executeCode(@[]) == 0
    check log == @["int", "void2"]

  test "execute still works with an int handler":
    var ran = false
    let root = newCommand("app")
    root.setRun proc(args: seq[string]): int =
      ran = true
      3
    root.execute(@[])
    check ran

  test "post hooks run after an int handler, error still wins":
    var log: seq[string]
    let root = newCommand("app")
    root.setRun proc(args: seq[string]): int =
      log.add "run"
      6
    root.setPostRun proc(args: seq[string]) =
      log.add "post"
    check root.executeCode(@[]) == 6
    check log == @["run", "post"]

  test "defineCommand int return becomes the exit code":
    proc answer(args: seq[string]): int =
      42
    defineCommand(answer, cmd)
    check cmd.executeCode(@[]) == 42

suite "ValueError from user parsers":
  test "becomes ParsingFlagError with flag and raw":
    var lv: Level
    let root = newCommand("app")
    root.addFlag("level", lv)
    let r = root.tryExecute(@["--level", "bad"])
    check r.error of ParsingFlagError
    let e = (ref ParsingFlagError)(r.error)
    check e.flag == "level"
    check e.raw == "bad"
    check "no such level" in e.msg
    check exitCode(e) == 2
    check root.tryExecute(@["--level", "ok"]).isOk

  test "also inside a separated list":
    var lvs: seq[Level]
    let root = newCommand("app")
    root.addFlag("level", lvs, sep = some(','))
    let r = root.tryExecute(@["--level", "a,bad"])
    check (ref ParsingFlagError)(r.error).raw == "bad"

  test "other exceptions stay failures":
    type Boom = object of CatchableError
    proc fromString(T: typedesc[Boom], r: string): Boom =
      raise newException(IOError, "disk")
    var b: Boom
    let root = newCommand("app")
    root.addFlag("b", b)
    expect IOError:
      discard root.tryExecute(@["--b", "x"])

suite "post hook errors":
  test "post error does not mask the run error":
    var log: seq[string]
    let root = newCommand("app")
    root.setRun proc(args: seq[string]) =
      raise newCliError("from run")
    root.setPostRun proc(args: seq[string]) =
      log.add "post"
      raise newCliError("from post")
    root.setPersistentPostRun proc(args: seq[string]) =
      log.add "pers"
    let child = newCommand("c")
    root.add child
    child.setRun proc(args: seq[string]) =
      raise newCliError("child run")
    let r = child.tryExecute(@[])
    check r.error.msg == "child run"
    let r2 = root.tryExecute(@[])
    check r2.error.msg == "from run"
    check log == @["post"]

  test "without a run error the first post error is raised, all posts run":
    var log: seq[string]
    let
      root = newCommand("app")
      leaf = newCommand("leaf")
    root.add leaf
    leaf.setPostRun proc(args: seq[string]) =
      log.add "leaf"
      raise newCliError("leaf post")
    root.setPersistentPostRun proc(args: seq[string]) =
      log.add "root"
      raise newCliError("root post")
    let r = root.tryExecute(@["leaf"])
    check r.error.msg == "leaf post"
    check log == @["leaf", "root"]

proc buildFixture(): string =
  let
    outDir = getTempDir() / "nimbra-exit"
    bin = outDir / "exit_demo_app"
  createDir(outDir)
  let cmd = quoteShellCommand([
    getCurrentCompilerExe(), "c", "--hints:off", "--verbosity:0",
    "--path:" & (root / "src"), "--nimcache:" & (outDir / "cache"),
    "-o:" & bin, root / "tests" / "exit_demo_app.nim",
  ])
  let (output, code) = execCmdEx(cmd)
  if code != 0:
    echo output
  doAssert code == 0
  bin

proc run(bin: string, args: openArray[string]): tuple[stdout, stderr: string, code: int] =
  let p = startProcess(bin, args = args, options = {})
  let o = p.outputStream.readAll()
  let e = p.errorStream.readAll()
  let c = p.waitForExit()
  p.close()
  (o, e, c)

suite "executeOrQuit":
  let bin = buildFixture()

  test "success":
    let r = run(bin, ["fine"])
    check r.code == 0
    check r.stdout == "fine\n"
    check r.stderr == ""

  test "explicit code and prefix on stderr":
    let r = run(bin, ["boom"])
    check r.code == 3
    check r.stdout == ""
    check r.stderr == "demo: error: preset missing\n"

  test "usage errors exit 2":
    let missing = run(bin, ["need"])
    check missing.code == 2
    check missing.stderr.startsWith("demo: error: Missing required flag --n")
    let unknown = run(bin, ["nope"])
    check unknown.code == 2
    check unknown.stderr ==
      "demo: error: unknown command 'nope' for 'demo'; available: boom, code, need, fine\n"
    let flag = run(bin, ["fine", "-z"])
    check flag.code == 2
    check "-z" in flag.stderr

  test "int handler result is the exit code":
    let r = run(bin, ["code"])
    check r.code == 4
    check r.stderr == ""
