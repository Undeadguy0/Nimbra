import std/paths
import std/os
import std/symlinks
import exceptions

type
  ## Parent dir exists, file/dir can be created
  FreePath* = distinct Path

  ## Path exists and it is a dir
  DirPath* = distinct Path

  ## Path exists and it is a file
  FilePath* = distinct Path

  ## Path exists and it is a symlink. Even it's broken
  SymPath* = distinct Path

  PathWrap* = FreePath | DirPath | FilePath | SymPath

proc fromString*[P: FreePath | DirPath | FilePath | SymPath](
    t: typedesc[P], r: string
): P =
  var fullPath = Path(r)
  if not fullPath.isAbsolute:
    fullPath = absolutePath(fullPath)
  let s = $fullPath

  when P is FreePath:
    let parent = os.parentDir(s)
    if not dirExists(parent):
      raise newException(
        ParsingFlagError, "FreePath: parent directory does not exist: " & parent
      )
    if symlinkExists(s) or fileExists(s) or dirExists(s):
      raise newException(ParsingFlagError, "FreePath: path already exists: " & s)
  elif P is DirPath:
    if symlinkExists(s):
      raise newException(
        ParsingFlagError, "DirPath: path is a symlink, not a directory: " & s
      )
    if not dirExists(s):
      raise newException(ParsingFlagError, "DirPath: not a directory: " & s)
  elif P is FilePath:
    if symlinkExists(s):
      raise
        newException(ParsingFlagError, "FilePath: path is a symlink, not a file: " & s)
    if not fileExists(s):
      raise newException(ParsingFlagError, "FilePath: not a file: " & s)
  elif P is SymPath:
    if not symlinkExists(s):
      raise newException(ParsingFlagError, "SymPath: not a symlink: " & s)

  P(fullPath)

proc toPath*(p: PathWrap): Path =
  Path(p)

template `$`*(p: PathWrap): string =
  string(p)
