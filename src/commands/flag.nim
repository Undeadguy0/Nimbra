## Набор флагов одной команды.
##
## Источник правды — `seq`. Таблицы хранят индекс в этой seq, не копию
## флага и не `ref`. Флаги только дописываются: удаление из середины
## сдвинуло бы индексы.
##
## Flag set of one command.
##
## The source of truth is a `seq`. The tables store an index into that seq,
## not a copy of the flag and not a `ref`. Flags are only appended: removing
## from the middle would shift the indexes.

import std/tables
import std/options
from ../exceptions import raiseCli

type
  Flag* = object
    ## Один флаг. `onValue` / `onAbsent` — замыкания на переменную пользователя.
    ## One flag. `onValue` / `onAbsent` are closures over the user's variable.
    name*: string
    aliases*: seq[string]
    short*: Option[char]
    help*: string
    persistent*: bool
    takesValue*: bool
    onValue*: proc(raw: string) {.closure.}
    onAbsent*: proc() {.closure.}

  FlagSet* = object
    flags: seq[Flag]
    byLong: Table[string, int]
    byShort: Table[char, int]

proc indexKeys(f: Flag): seq[string] =
  ## Имя и алиасы, которые займут `byLong`. Пустое и повтор внутри флага — ошибка.
  ## Name and aliases that will occupy `byLong`. Empty or an internal duplicate is an error.
  if f.name.len == 0:
    raiseCli("flag without name")
  result = @[f.name]
  for a in f.aliases:
    if a.len == 0:
      raiseCli("empty flag alias", f.name)
    if a in result:
      raiseCli("duplicate flag: --" & a, a)
    result.add a

proc rejectOccupied(s: FlagSet, f: Flag, keys: seq[string]) =
  for n in keys:
    if n in s.byLong:
      raiseCli("duplicate flag: --" & n, n)
  if f.short.isSome:
    let ch = f.short.get
    if ch in s.byShort:
      raiseCli("duplicate flag: -" & $ch, $ch)

proc checkAdd*(s: FlagSet, f: Flag) =
  ## Те же отказы, что у `add`, но набор не меняет.
  ## Регистрация сначала обходит поддерево и только потом копирует флаги.
  ## The same rejections as `add`, without changing the set.
  ## Registration walks the subtree first and copies flags only after that.
  let keys = indexKeys(f)
  rejectOccupied(s, f, keys)

proc add*(s: var FlagSet, f: Flag) =
  ## Кладёт флаг в конец. Повтор имени, алиаса или короткого имени — ошибка регистрации.
  ## Appends a flag. A repeated name, alias, or short name is a registration error.
  let keys = indexKeys(f)
  rejectOccupied(s, f, keys)
  let idx = s.flags.len
  s.flags.add f
  for n in keys:
    s.byLong[n] = idx
  if f.short.isSome:
    s.byShort[f.short.get] = idx

proc findLong*(s: FlagSet, name: string): Option[int] =
  ## Индекс флага по длинному имени или алиасу.
  ## Flag index by long name or alias.
  if name in s.byLong:
    some(s.byLong[name])
  else:
    none(int)

proc findShort*(s: FlagSet, ch: char): Option[int] =
  if ch in s.byShort:
    some(s.byShort[ch])
  else:
    none(int)

proc len*(s: FlagSet): int =
  s.flags.len

proc takesValue*(s: FlagSet, i: int): bool =
  s.flags[i].takesValue

proc longName*(s: FlagSet, i: int): string =
  ## Каноническое имя, без ведущих дефисов.
  ## Canonical name, without leading dashes.
  s.flags[i].name

proc invokeValue*(s: FlagSet, i: int, raw: string) =
  ## Замыкание копируется как ref и живёт дольше временной копии `Flag`.
  ## The closure is copied as a ref and outlives the temporary `Flag` copy.
  let fn = s.flags[i].onValue
  fn(raw)

proc invokeAbsent*(s: FlagSet, i: int) =
  let fn = s.flags[i].onAbsent
  fn()

proc persistentFlags*(s: FlagSet): seq[Flag] =
  ## Копии для потомков. Замыкание общее, индекс у потомка будет свой.
  ## Copies for descendants. The closure is shared; the child's index is its own.
  for f in s.flags:
    if f.persistent:
      result.add f
