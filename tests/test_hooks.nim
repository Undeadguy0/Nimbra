import std/options
import std/unittest
import results
import nimbra

type AppErr = object
  text: string

proc toCliError(e: AppErr): ref CliError =
  newException(CliError, e.text)

suite "хуки":
  test "цепочка persistent и локальные предков молчат":
    var log: seq[string]
    let
      root = newCommand("app")
      mid = newCommand("mid")
      leaf = newCommand("leaf")
    root.add mid
    mid.add leaf
    root.setPersistentPreRun proc(args: seq[string]) =
      log.add "root-pers-pre"
    root.setPreRun proc(args: seq[string]) =
      log.add "root-pre"
    mid.setPersistentPreRun proc(args: seq[string]) =
      log.add "mid-pers-pre"
    mid.setPreRun proc(args: seq[string]) =
      log.add "mid-pre"
    leaf.setPreRun proc(args: seq[string]) =
      log.add "leaf-pre:" & args[0]
    leaf.setRun proc(args: seq[string]) =
      log.add "run"
    leaf.setPostRun proc(args: seq[string]) =
      log.add "leaf-post"
    mid.setPersistentPostRun proc(args: seq[string]) =
      log.add "mid-pers-post"
    root.setPersistentPostRun proc(args: seq[string]) =
      log.add "root-pers-post"
    check root.tryExecute(@["mid", "leaf", "file"]).isOk
    check log ==
      @[
        "root-pers-pre", "mid-pers-pre", "leaf-pre:file", "run", "leaf-post",
        "mid-pers-post", "root-pers-post",
      ]

  test "ошибка run не пропускает post, ошибка pre до run не доходит":
    var log: seq[string]
    let root = newCommand("app")
    root.setRun proc(args: seq[string]) =
      log.add "run"
      raise newException(CliError, "from run")
    root.setPostRun proc(args: seq[string]) =
      log.add "post"
    let failed = root.tryExecute(@[])
    check failed.isErr
    check failed.error.msg == "from run"
    check log == @["run", "post"]

    log.setLen 0
    let other = newCommand("app")
    other.setPreRun proc(args: seq[string]) =
      log.add "pre"
      raise newException(CliError, "from pre")
    other.setRun proc(args: seq[string]) =
      log.add "run"
    other.setPostRun proc(args: seq[string]) =
      log.add "post"
    check other.tryExecute(@[]).isErr
    check log == @["pre"]

  test "Result и свой toCliError, прочий CatchableError не прячется":
    let root = newCommand("app")
    root.setRun proc(args: seq[string]): Result[void, string] =
      if args.len == 0:
        return err("need arg")
      ok()
    check root.tryExecute(@["x"]).isOk
    let missing = root.tryExecute(@[])
    check missing.isErr
    check missing.error.msg == "need arg"
    check not (missing.error of ParsingFlagError)

    let custom = newCommand("app")
    custom.setRun proc(args: seq[string]): Result[void, AppErr] =
      err(AppErr(text: "boom"))
    check custom.tryExecute(@[]).error.msg == "boom"

    let buggy = newCommand("app")
    buggy.setRun proc(args: seq[string]) =
      raise newException(ValueError, "bug")
    expect ValueError:
      discard buggy.tryExecute(@[])

  test "группа без run запускается":
    let
      root = newCommand("app")
      sub = newCommand("sub")
    root.add sub
    check root.tryExecute(@["sub"]).isOk

  test "свой persistent молчит, когда выбрана сама команда":
    var log: seq[string]
    let
      root = newCommand("app")
      sub = newCommand("sub")
    root.add sub
    root.setPersistentPreRun proc(args: seq[string]) =
      log.add "root-pers-pre"
    root.setPreRun proc(args: seq[string]) =
      log.add "root-pre"
    root.setRun proc(args: seq[string]) =
      log.add "root-run"
    root.setPostRun proc(args: seq[string]) =
      log.add "root-post"
    root.setPersistentPostRun proc(args: seq[string]) =
      log.add "root-pers-post"
    sub.setPersistentPreRun proc(args: seq[string]) =
      log.add "sub-pers-pre"
    sub.setRun proc(args: seq[string]) =
      log.add "sub-run:" & args[0]
    check root.tryExecute(@["file"]).isOk
    check log == @["root-pre", "root-run", "root-post"]
    log.setLen 0
    check root.tryExecute(@["sub", "a", "b"]).isOk
    check log == @["root-pers-pre", "sub-run:a", "root-pers-post"]

  test "повторный setRun заменяет обработчик":
    var n = 0
    let root = newCommand("app")
    root.setRun proc(args: seq[string]) =
      n = 1
    root.setRun proc(args: seq[string]) =
      n = 2
    check root.tryExecute(@[]).isOk
    check n == 2

  test "ошибка post заменяет ошибку run и обрывает хвост":
    var log: seq[string]
    let
      root = newCommand("app")
      sub = newCommand("sub")
    root.add sub
    sub.setRun proc(args: seq[string]) =
      log.add "run"
      raise newException(CliError, "from run")
    sub.setPostRun proc(args: seq[string]) =
      log.add "post"
      raise newException(CliError, "from post")
    root.setPersistentPostRun proc(args: seq[string]) =
      log.add "root-pers-post"
    let failed = root.tryExecute(@["sub"])
    check failed.error.msg == "from post"
    check log == @["run", "post"]

  test "Result на pre и persistent post":
    let root = newCommand("app")
    root.setPreRun proc(args: seq[string]): Result[void, string] =
      err("from pre")
    check root.tryExecute(@[]).error.msg == "from pre"

    let boom = newParsingFlagError("bad", raw = "x", flag = "f")
    let custom = newCommand("app")
    custom.setPersistentPostRun proc(args: seq[string]): Result[void, ref CliError] =
      err(boom)
    let sub = newCommand("sub")
    custom.add sub
    sub.setRun proc(args: seq[string]) =
      discard
    let failed = custom.tryExecute(@["sub"])
    check failed.error == boom
    check (ref ParsingFlagError)(failed.error).raw == "x"
    check (ref ParsingFlagError)(failed.error).flag == "f"
