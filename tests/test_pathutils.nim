import std/os
import std/paths
import std/tempfiles
import std/unittest
import nimbra
import pathutils

suite "pathutils":
  setup:
    let
      oldDir = os.getCurrentDir()
      tmp = createTempDir("nimbra_", "_paths")
    createDir(tmp / "sub")
    writeFile(tmp / "file.txt", "x")
    createSymlink(tmp / "file.txt", tmp / "link")
    setCurrentDir(tmp)

  teardown:
    setCurrentDir(oldDir)
    removeDir(tmp)

  test "relative paths resolve against current directory":
    check $fromString(DirPath, "sub") == tmp / "sub"
    check $fromString(FilePath, "file.txt") == tmp / "file.txt"
    check $fromString(SymPath, "link") == tmp / "link"
    check $fromString(FreePath, "new.txt") == tmp / "new.txt"
    check $fromString(FreePath, "sub/new.txt") == tmp / "sub" / "new.txt"
    check fromString(DirPath, "sub").toPath.isAbsolute

  test "absolute paths pass through unchanged":
    check $fromString(DirPath, tmp / "sub") == tmp / "sub"
    check $fromString(FilePath, tmp / "file.txt") == tmp / "file.txt"
    check $fromString(SymPath, tmp / "link") == tmp / "link"
    check $fromString(FreePath, tmp / "new.txt") == tmp / "new.txt"

  test "invalid input is rejected":
    expect ParsingFlagError:
      discard fromString(DirPath, "file.txt")
    expect ParsingFlagError:
      discard fromString(DirPath, "link")
    expect ParsingFlagError:
      discard fromString(FilePath, "sub")
    expect ParsingFlagError:
      discard fromString(FilePath, "link")
    expect ParsingFlagError:
      discard fromString(SymPath, "file.txt")
    expect ParsingFlagError:
      discard fromString(FreePath, "file.txt")
    expect ParsingFlagError:
      discard fromString(FreePath, "missing/new.txt")

  test "path kinds are distinct types":
    let d = fromString(DirPath, "sub")
    check d is DirPath
    check d.toPath is Path
    check not compiles(block:
      let f: FilePath = d)
    check not compiles(block:
      let p: Path = d)
    check not compiles(block:
      let s: string = d)
