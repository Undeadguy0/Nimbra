## Собирает примеры из `examples/` и гоняет их как отдельный процесс.
## Builds the examples from `examples/` and runs them as a separate process.

import std/os
import std/osproc
import std/streams
import std/strutils
import std/unittest

const root = currentSourcePath().parentDir.parentDir

proc buildExample(name: string): string =
  ## Возвращает путь к бинарнику. Собирает во временный каталог, не в дерево.
  ## Returns the binary path. Builds into a temp dir, not into the tree.
  let
    src = root / "examples" / name / "src" / (name & ".nim")
    outDir = getTempDir() / "nimbra-examples"
    bin = outDir / name
  createDir(outDir)
  let cmd = quoteShellCommand([
    getCurrentCompilerExe(), "c", "--hints:off", "--verbosity:0",
    "--path:" & (root / "src"), "--nimcache:" & (outDir / ("cache-" & name)),
    "-o:" & bin, src,
  ])
  let (output, code) = execCmdEx(cmd)
  if code != 0:
    echo output
  doAssert code == 0, "example " & name & " does not build"
  bin

proc run(bin: string, args: openArray[string]): tuple[stdout, stderr: string, code: int] =
  let p = startProcess(bin, args = args, options = {})
  let o = p.outputStream.readAll()
  let e = p.errorStream.readAll()
  let c = p.waitForExit()
  p.close()
  (o, e, c)

suite "examples":
  let calc = buildExample("simple_calc")

  test "simple_calc computes":
    let r = run(calc, ["-o", "Add", "1", "2.5"])
    check r.code == 0
    check r.stdout.strip == "3.5"
    check r.stderr.len == 0

  test "simple_calc reports errors on stderr with nonzero exit":
    let unknown = run(calc, ["--nope", "1"])
    check unknown.code != 0
    check unknown.stdout.len == 0
    check "unknown flag" in unknown.stderr
    let missing = run(calc, ["1"])
    check missing.code != 0
    check "operation" in missing.stderr

  test "simple_calc rejects a number with junk":
    let bad = run(calc, ["-o", "Add", "12abc"])
    check bad.code != 0
    check "12abc" in bad.stderr
