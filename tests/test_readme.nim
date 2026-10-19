## Каждый блок ```nim из README обязан компилироваться.
## Every ```nim block in the README must compile.

import std/os
import std/osproc
import std/strutils
import std/unittest

const root = currentSourcePath().parentDir.parentDir

proc nimBlocks(text: string): seq[string] =
  var
    inside = false
    current: seq[string]
  for line in text.splitLines:
    if not inside and line.strip == "```nim":
      inside = true
      current = @[]
    elif inside and line.strip == "```":
      inside = false
      let code = current.join("\n")
      if code notin result:
        result.add code
    elif inside:
      current.add line

suite "README":
  let blocks = nimBlocks(readFile(root / "README.md"))

  test "has a usage example":
    check blocks.len >= 2

  test "every nim block compiles":
    let dir = getTempDir() / "nimbra-readme"
    createDir(dir)
    for i, code in blocks:
      let file = dir / ("block" & $i & ".nim")
      writeFile(file, code)
      let cmd = quoteShellCommand([
        getCurrentCompilerExe(), "check", "--hints:off",
        "--path:" & (root / "src"), file,
      ])
      let (output, exitCode) = execCmdEx(cmd)
      if exitCode != 0:
        echo "README block ", i, ":\n", code, "\n", output
      check exitCode == 0
