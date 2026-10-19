## Дерево команд, регистрация флагов, разбор argv и запуск хуков.
##
## Парсер не вызывает хуки. Он только зовёт `onValue` / `onAbsent`.
## Обязательность, дефолт и смысл bool сидят в замыкании, которое
## собирает `addFlag`. Указателя на родителя нет: путь root..leaf
## живёт в `Parsed`.
##
## Command tree, flag registration, argv parsing, and hook launch.
##
## The parser does not call hooks. It only calls `onValue` / `onAbsent`.
## Required, default, and the meaning of bool live in the closure that
## `addFlag` builds. There is no parent pointer: the root..leaf path
## lives in `Parsed`.
##
## Время жизни переменной
## ----------------------
##
## `addFlag` запоминает адрес `output`, а не копию. Переменная обязана
## жить, пока команда может разбираться: до последнего `parse` / `execute`
## этого дерева. Глобальная переменная или локальная в той же процедуре,
## где вызывается `execute`, — безопасно. Локальная переменная процедуры,
## которая только собирает дерево и возвращает `Command`, — висячий
## указатель: после возврата запись идёт в чужую память.
##
## Variable lifetime
## -----------------
##
## `addFlag` stores the address of `output`, not a copy. The variable must
## stay alive for as long as the command can be parsed: until the last
## `parse` / `execute` of this tree. A global, or a local of the same
## procedure that calls `execute`, is safe. A local of a procedure that only
## builds the tree and returns the `Command` is a dangling pointer: after
## that procedure returns, writes land in someone else's memory.

import std/options
import std/os
from std/parseutils import parseFloat
import std/strutils
import results
import ../exceptions
import ../stdconv
import arg_limits
import flag


type
  Handler* = proc(args: seq[string]) {.closure.}
  CodeHandler* = proc(args: seq[string]): int {.closure.}
    ## Обработчик run, возвращающий код выхода. / A run handler that returns an exit code.
  Command* = ref object
    ## Узел дерева. Дети — seq, порядок нужен для help и поиска.
    ## A tree node. Children are a seq; order is needed for help and lookup.
    name*: string
    help*: string
    aliases: seq[string]
    argLimit*: ArgLimit
    runImpl: Option[Handler]
    runCodeImpl: Option[CodeHandler]
    preRunImpl: Option[Handler]
    postRunImpl: Option[Handler]
    persPreRunImpl: Option[Handler]
    persPostRunImpl: Option[Handler]
    subcommands: seq[Command]
    flags: FlagSet

  Parsed* = object
    ## Результат разбора без хуков. `path[0]` — корень, последний — выбранная команда.
    ## Parse result without hooks. `path[0]` is the root, the last item is the selected command.
    path*: seq[Command]
    args*: seq[string]

proc newCommand*(name: string, help = "", aliases: seq[string] = @[]): Command =
  ## Корень тоже создаётся здесь. Пустое имя допустимо только у корня:
  ## `add` пустое имя ребёнка отвергает.
  ## The root is created here too. An empty name is allowed only on the root:
  ## `add` rejects an empty child name.
  result = Command(name: name, help: help, aliases: aliases)
  var seen: seq[string] = @[]
  if name.len > 0:
    seen.add name
  for a in aliases:
    if a.len == 0 or a in seen:
      let msg =
        if a.len == 0:
          "empty command alias"
        else:
          "duplicate command name: " & a
      raiseCli(msg)
    seen.add a

template declareHook(setName, field: untyped) =
  proc setName*(c: Command, body: Handler) =
    c.field = some(body)
    when astToStr(field) == "runImpl":
      c.runCodeImpl = none(CodeHandler)

  proc setName*[E](c: Command, body: proc(args: seq[string]): Result[void, E]) =
    ## Ошибка Result становится `raise` до записи в узел.
    ## `mixin` оставляет `toCliError` открытым для типа пользователя.
    ## A Result error becomes `raise` before it is stored on the node.
    ## `mixin` keeps `toCliError` open for the user's error type.
    c.field = some(
      proc(args: seq[string]) =
        let r = body(args)
        if r.isErr:
          mixin toCliError
          raise r.error.toCliError()
    )
    when astToStr(field) == "runImpl":
      c.runCodeImpl = none(CodeHandler)

declareHook(setRun, runImpl)

proc setRun*(c: Command, body: CodeHandler) =
  ## Обработчик возвращает код выхода. Заменяет обработчик без кода.
  ## Код доставляют `executeCode` / `tryExecuteCode` / `executeOrQuit`;
  ## `execute` его отбрасывает.
  ## The handler returns the exit code. Replaces a handler without a code.
  ## `executeCode` / `tryExecuteCode` / `executeOrQuit` deliver the code;
  ## `execute` discards it.
  c.runCodeImpl = some(body)
  c.runImpl = none(Handler)
declareHook(setPreRun, preRunImpl)
declareHook(setPostRun, postRunImpl)
declareHook(setPersistentPreRun, persPreRunImpl)
declareHook(setPersistentPostRun, persPostRunImpl)

proc namesOf(c: Command): seq[string] =
  result = @[c.name]
  for a in c.aliases:
    result.add a

proc overlaps(a, b: Command): bool =
  for left in namesOf(a):
    if left.len == 0:
      continue
    for right in namesOf(b):
      if left == right:
        return true
  false

proc ensureFits(node: Command, f: Flag) =
  node.flags.checkAdd(f)
  for child in node.subcommands:
    ensureFits(child, f)

proc spreadPersistent(node: Command, f: Flag) =
  node.flags.add f
  for child in node.subcommands:
    spreadPersistent(child, f)

proc add*(parent, child: Command) =
  ## Вешает ребёнка. Persistent-флаги родителя копируются ему и уже
  ## существующим потомкам через тот же `FlagSet.add`.
  ## Сначала проверка всего поддерева: ошибка не оставляет флаг наполовину.
  ## Attaches a child. The parent's persistent flags are copied onto it and
  ## onto descendants that already exist, through the same `FlagSet.add`.
  ## The whole subtree is checked first: an error does not leave a flag half-applied.
  if child.name.len == 0:
    raiseCli("command without name")
  for sib in parent.subcommands:
    if overlaps(sib, child):
      raiseCli("duplicate command: " & child.name)
  for f in parent.flags.persistentFlags:
    ensureFits(child, f)
  for f in parent.flags.persistentFlags:
    spreadPersistent(child, f)
  parent.subcommands.add child

proc findChild(parent: Command, tok: string): Option[Command] =
  for child in parent.subcommands:
    if child.name == tok:
      return some(child)
    for a in child.aliases:
      if a == tok:
        return some(child)
  none(Command)

proc attach(c: Command, f: Flag) =
  ## Свой набор и, для persistent, всё поддерево. Запись начинается
  ## после проверки, чтобы отказ на внуке не оставлял флаг у предка.
  ## This command's set and, for a persistent flag, the whole subtree.
  ## Writing starts after the check, so a clash on a grandchild does not
  ## leave the flag on an ancestor.
  c.flags.checkAdd(f)
  if f.persistent:
    for child in c.subcommands:
      ensureFits(child, f)
  c.flags.add f
  if f.persistent:
    for child in c.subcommands:
      spreadPersistent(child, f)

proc guardPolicy(name: string, required: bool, hasDefault: bool, isBool: bool) =
  if required and hasDefault:
    raiseCli("flag cannot be both required and have a default", name)
  if required and isBool:
    raiseCli("bool flag cannot be required", name)

template stamp(name, raw: string, body: untyped) =
  ## Дописывает имя и raw в уже поднятый `ParsingFlagError` и кидает его дальше.
  ## Шаблон, а не proc: запись в переменную остаётся в замыкании флага.
  ## Fills the name and raw on an already raised `ParsingFlagError` and raises it again.
  ## A template, not a proc: the write to the variable stays inside the flag closure.
  try:
    body
  except ParsingFlagError as e:
    e.flag = name
    e.raw = raw
    raise e
  except ValueError as e:
    # Пользовательский `fromString` может кинуть ValueError: это тоже
    # плохое значение флага, а не сбой программы.
    # A user `fromString` may raise ValueError: that is a bad flag value too,
    # not a program failure.
    raise newParsingFlagError(e.msg, raw, name)

proc addFlag*[T: CliValue](
    c: Command,
    name: string,
    output: var T,
    default: Option[T] = none(T),
    required = false,
    aliases: seq[string] = @[],
    short: Option[char] = none(char),
    help: string = "",
    persistent = false,
) =
  ## Скаляр. Последнее упоминание заменяет значение.
  ## Без `required` и без явного дефолта отсутствие переменную не трогает.
  ## Scalar. The last mention replaces the value.
  ## Without `required` and without an explicit default, absence leaves the variable alone.
  when T is bool:
    guardPolicy(name, required, default.isSome, true)
    const takes = false
  else:
    guardPolicy(name, required, default.isSome, false)
    const takes = true
  let
    canonical = name
    fallback = default
    must = required
    # Замыкание не может захватить var-параметр, поэтому храним адрес.
    # См. «Время жизни переменной» в описании модуля.
    # A closure cannot capture a var parameter, so the address is stored.
    # See "Variable lifetime" in the module doc.
    slot = addr output
  let onValue = proc(raw: string) =
    # Пустая строка — законное значение строкового флага, не «нет значения».
    # An empty string is a real value of a string flag, not "no value".
    when T is string:
      const emptyIsValue = true
    else:
      const emptyIsValue = false
    if raw.len == 0 and fallback.isSome and not emptyIsValue:
      slot[] = fallback.get
    elif raw.len == 0 and not emptyIsValue:
      when T is bool:
        slot[] = false
      else:
        stamp(canonical, raw):
          mixin fromString
          slot[] = fromString(T, raw)
    else:
      stamp(canonical, raw):
        mixin fromString
        slot[] = fromString(T, raw)
  let onAbsent = proc() =
    when T is bool:
      if fallback.isSome:
        slot[] = fallback.get
      else:
        slot[] = false
    else:
      if fallback.isSome:
        slot[] = fallback.get
      elif must:
        raise newMissingFlagError("flag not present", canonical)
  c.attach(
    Flag(
      name: name,
      aliases: aliases,
      short: short,
      help: help,
      persistent: persistent,
      takesValue: takes,
      onValue: onValue,
      onAbsent: onAbsent,
    )
  )

proc addFlag*[T: CliValue](
    c: Command,
    name: string,
    output: var seq[T],
    default: Option[seq[T]] = none(seq[T]),
    required = false,
    aliases: seq[string] = @[],
    short: Option[char] = none(char),
    help: string = "",
    persistent = false,
    sep: Option[char] = none(char),
) =
  ## Повтор флага дописывает элементы. Без `sep` каждое упоминание — один
  ## элемент, и пустой raw — raw элемента, не повод подставить дефолт списка.
  ## С `sep` значение режется по разделителю (`--only a,b`), пустые
  ## сегменты пропускаются, пустое значение не добавляет ничего. В
  ## `ParsingFlagError.raw` попадает сегмент, а не весь токен.
  ## Each repeat appends elements. Without `sep` each mention is one element,
  ## and an empty raw is that element's raw, not a reason to substitute the
  ## list default. With `sep` the value is split on the separator
  ## (`--only a,b`), empty segments are skipped, an empty value adds nothing.
  ## `ParsingFlagError.raw` carries the segment, not the whole token.
  guardPolicy(name, required, default.isSome, false)
  let
    canonical = name
    fallback = default
    must = required
    slot = addr output
  let splitter = sep
  let onValue = proc(raw: string) =
    if splitter.isNone:
      stamp(canonical, raw):
        mixin fromString
        slot[].add fromString(T, raw)
    else:
      var parsed: seq[T]
      for segment in raw.split(splitter.get):
        if segment.len == 0:
          continue
        # Имя `raw` нужно шаблону `stamp`: он пишет `e.raw = raw`.
        # The template `stamp` needs the name `raw`: it writes `e.raw = raw`.
        let raw = segment
        stamp(canonical, raw):
          mixin fromString
          parsed.add fromString(T, raw)
      slot[].add parsed
  let onAbsent = proc() =
    if fallback.isSome:
      slot[] = fallback.get
    elif must:
      raise newMissingFlagError("flag not present", canonical)
  c.attach(
    Flag(
      name: name,
      aliases: aliases,
      short: short,
      help: help,
      persistent: persistent,
      takesValue: true,
      onValue: onValue,
      onAbsent: onAbsent,
    )
  )

proc addFlag*[T: CliValue](
    c: Command,
    name: string,
    output: var Option[T],
    default: Option[T] = none(T),
    required = false,
    aliases: seq[string] = @[],
    short: Option[char] = none(char),
    help: string = "",
    persistent = false,
) =
  ## `default` — внутренний `T`. В переменную пишется `some`, не вложенный option.
  ## Отсутствие без дефолта и без `required` ставит `none`, даже если там уже было значение.
  ## `default` is the inner `T`. The variable receives `some`, not a nested option.
  ## Absence without a default and without `required` stores `none`, even if a value was already there.
  guardPolicy(name, required, default.isSome, false)
  let
    canonical = name
    fallback = default
    must = required
    slot = addr output
  let onValue = proc(raw: string) =
    when T is string:
      const emptyIsValue = true
    else:
      const emptyIsValue = false
    if raw.len == 0 and fallback.isSome and not emptyIsValue:
      slot[] = some(fallback.get)
    else:
      stamp(canonical, raw):
        mixin fromString
        slot[] = some(fromString(T, raw))
  let onAbsent = proc() =
    if must:
      raise newMissingFlagError("flag not present", canonical)
    elif fallback.isSome:
      slot[] = some(fallback.get)
    else:
      slot[] = none(T)
  c.attach(
    Flag(
      name: name,
      aliases: aliases,
      short: short,
      help: help,
      persistent: persistent,
      takesValue: true,
      onValue: onValue,
      onAbsent: onAbsent,
    )
  )

proc isLongFlag(tok: string): bool =
  tok.len > 2 and tok.startsWith("--")

proc isShortFlag(tok: string): bool =
  tok.len >= 2 and tok[0] == '-' and tok[1] != '-'

proc looksNegativeNumber(tok: string): bool =
  ## `-` и дальше число на весь токен: `-4`, `-3.5`, `-.5`, `-1e3`.
  ## `-` followed by a number filling the whole token: `-4`, `-3.5`, `-.5`, `-1e3`.
  if tok.len < 2 or tok[0] != '-' or tok[1] notin {'0' .. '9', '.'}:
    return false
  var f = 0.0
  try:
    parseFloat(tok, f) == tok.len
  except ValueError:
    false

proc isNegativeNumber(cmd: Command, tok: string): bool =
  ## Короткий флаг-цифра, если он зарегистрирован, важнее числа.
  ## A registered digit short flag wins over the number.
  looksNegativeNumber(tok) and cmd.flags.findShort(tok[1]).isNone

proc isFlagToken(cmd: Command, tok: string): bool =
  (isLongFlag(tok) or isShortFlag(tok)) and not isNegativeNumber(cmd, tok)

proc missingValue(flagName, raw: string) {.noreturn.} =
  raise newParsingFlagError("missing value", raw = raw, flag = flagName)

proc unknownFlag(flagName, raw: string, isShort = false) {.noreturn.} =
  raise newParsingFlagError("unknown flag", raw = raw, flag = flagName, isShort = isShort)

proc takeNext(tokens: seq[string], i: var int, flagName, raw: string): string =
  if i + 1 >= tokens.len or tokens[i + 1] == "--":
    missingValue(flagName, raw)
  result = tokens[i + 1]
  inc i

proc splitLong(tok: string): tuple[key, raw: string, hasEq: bool] =
  let body = tok[2 .. ^1]
  let eq = body.find('=')
  if eq >= 0:
    (body[0 ..< eq], body[eq + 1 .. ^1], true)
  else:
    (body, "", false)

proc skipFlag(cmd: Command, tokens: seq[string], i: var int): bool =
  ## Поиск команды: перешагнуть флаг и его значение, ничего не вызывая.
  ## `false` — флаг этой команде неизвестен: поиск команды на этом стоп,
  ## ошибку сообщит разбор флагов.
  ## Command lookup: step over a flag and its value without calling anything.
  ## `false` means this command does not know the flag: the lookup stops here
  ## and flag parsing reports the error.
  let tok = tokens[i]
  var takesNext = false
  if isLongFlag(tok):
    let (key, _, hasEq) = splitLong(tok)
    let idx = cmd.flags.findLong(key)
    if idx.isNone:
      return false
    takesNext = cmd.flags.takesValue(idx.get) and not hasEq
  else:
    let cluster = tok[1 .. ^1]
    var k = 0
    while k < cluster.len:
      let idx = cmd.flags.findShort(cluster[k])
      if idx.isNone:
        return false
      if cmd.flags.takesValue(idx.get):
        takesNext = k + 1 == cluster.len
        break
      if k + 1 < cluster.len and cluster[k + 1] == '=':
        break
      inc k
  inc i
  if takesNext and i < tokens.len and tokens[i] != "--":
    inc i
  true

proc parseLong(
    cmd: Command, tok: string, tokens: seq[string], i: var int, seen: var seq[bool]
) =
  var (key, raw, hasEq) = splitLong(tok)
  if key.len == 0:
    unknownFlag("", tok)
  let idxOpt = cmd.flags.findLong(key)
  if idxOpt.isNone:
    unknownFlag(key, tok)
  let idx = idxOpt.get
  let canonical = cmd.flags.longName(idx)
  if cmd.flags.takesValue(idx):
    if not hasEq:
      raw = takeNext(tokens, i, canonical, tok)
  else:
    if not hasEq:
      raw = "true"
  seen[idx] = true
  cmd.flags.invokeValue(idx, raw)
  inc i

proc parseShort(
    cmd: Command, tok: string, tokens: seq[string], i: var int, seen: var seq[bool]
) =
  ## `-abc` — кластер. Флаг со значением забирает остаток кластера
  ## (`-p80`, `-p=80`) или следующий токен. Bool принимает `-v=false`.
  ## `-abc` is a cluster. A value flag takes the rest of the cluster
  ## (`-p80`, `-p=80`) or the next token. A bool accepts `-v=false`.
  let cluster = tok[1 .. ^1]
  var k = 0
  while k < cluster.len:
    let ch = cluster[k]
    let idxOpt = cmd.flags.findShort(ch)
    if idxOpt.isNone:
      unknownFlag($ch, tok, isShort = true)
    let idx = idxOpt.get
    let canonical = cmd.flags.longName(idx)
    let hasEq = k + 1 < cluster.len and cluster[k + 1] == '='
    if cmd.flags.takesValue(idx):
      var raw: string
      if hasEq:
        raw = cluster[k + 2 .. ^1]
      elif k + 1 < cluster.len:
        raw = cluster[k + 1 .. ^1]
      else:
        raw = takeNext(tokens, i, canonical, tok)
      seen[idx] = true
      cmd.flags.invokeValue(idx, raw)
      break
    seen[idx] = true
    if hasEq:
      cmd.flags.invokeValue(idx, cluster[k + 2 .. ^1])
      break
    cmd.flags.invokeValue(idx, "true")
    inc k
  inc i

proc finishAbsent(cmd: Command, seen: seq[bool]) =
  for idx in 0 ..< cmd.flags.len:
    if not seen[idx]:
      cmd.flags.invokeAbsent(idx)

proc parse*(root: Command, tokens: seq[string]): Parsed =
  ## Два прохода.
  ##
  ## 1. Поиск команды. Флаги, известные текущей команде, перешагиваются
  ##    вместе со значением, так что persistent-флаг корня можно написать
  ##    до подкоманды. Поиск стоп на `--`, на первом позиционном, который не
  ##    подкоманда, и на флаге, неизвестном текущей команде.
  ## 2. Флаги выбранной команды в любом месте остатка, между позиционными
  ##    тоже. `--` заканчивает флаги. Отрицательное число (`-4`, `-1.5`) —
  ##    позиционный, если у команды нет такого короткого флага-цифры.
  ##
  ## Отметки «флаг встретился» живут только в этом вызове.
  ##
  ## Two passes.
  ##
  ## 1. Command lookup. Flags known to the current command are stepped over
  ##    with their value, so a root persistent flag may come before the
  ##    subcommand. The lookup stops at `--`, at the first positional that is
  ##    not a subcommand, and at a flag the current command does not know.
  ## 2. Flags of the selected command anywhere in the rest, between
  ##    positionals too. `--` ends flags. A negative number (`-4`, `-1.5`) is
  ##    a positional unless the command has that digit as a short flag.
  ##
  ## "Flag was seen" marks live only for this call.
  var
    path = @[root]
    current = root
    rest: seq[string]
    i = 0
  while i < tokens.len:
    let tok = tokens[i]
    if tok == "--":
      break
    if isFlagToken(current, tok):
      let start = i
      if not skipFlag(current, tokens, i):
        break
      rest.add tokens[start ..< i]
      continue
    let child = findChild(current, tok)
    if child.isNone:
      break
    current = child.get
    path.add current
    inc i
  if i < tokens.len:
    rest.add tokens[i .. ^1]

  var seen = newSeq[bool](current.flags.len)
  var args: seq[string]
  i = 0
  while i < rest.len:
    let tok = rest[i]
    if tok == "--":
      args.add rest[i + 1 .. ^1]
      break
    elif isFlagToken(current, tok):
      if isLongFlag(tok):
        parseLong(current, tok, rest, i, seen)
      else:
        parseShort(current, tok, rest, i, seen)
    else:
      args.add tok
      inc i
  finishAbsent(current, seen)
  Parsed(path: path, args: args)

proc describeLimit(limit: ArgLimit): string =
  if limit.max.isSome and limit.max.get == limit.min:
    "exactly " & $limit.min
  elif limit.max.isNone:
    "at least " & $limit.min
  elif limit.min == 0:
    "at most " & $limit.max.get
  else:
    "between " & $limit.min & " and " & $limit.max.get

proc checkArgs(cmd: Command, args: seq[string]) =
  if cmd.argLimit.holds(args.len):
    return
  let n = uint(args.len)
  raise newArgCountError(
    "expected " & describeLimit(cmd.argLimit) & " positional arguments, got " & $n,
    n,
    cmd.argLimit.min,
    cmd.argLimit.max,
  )

proc checkCommand(cmd: Command, args: seq[string]) =
  ## Родитель без своего run позиционные не принимает: первый из них —
  ## опечатка в имени подкоманды.
  ## A parent without its own run takes no positionals: the first one is a
  ## mistyped subcommand name.
  if args.len == 0 or cmd.subcommands.len == 0 or cmd.runImpl.isSome:
    return
  var names: seq[string]
  for child in cmd.subcommands:
    names.add child.name
  raise newUnknownCommandError(args[0], cmd.name, names)

proc callHook(slot: Option[Handler], args: seq[string]) =
  if slot.isSome:
    slot.get()(args)

proc runHooks(parsed: Parsed): int =
  ## Ошибка pre-хука обрывает всё. Post-хуки идут всегда после run; все
  ## выполняются, наружу выходит ошибка run, а если её нет — первая
  ## ошибка post-хука.
  ## A pre-hook error aborts everything. Post hooks always run after run;
  ## all of them run, and the run error is raised, or, without one, the
  ## first post-hook error.
  let
    path = parsed.path
    args = parsed.args
    cmd = path[^1]
  for anc in path[0 ..< ^1]:
    callHook(anc.persPreRunImpl, args)
  callHook(cmd.preRunImpl, args)
  var failure: ref Exception = nil
  try:
    if cmd.runCodeImpl.isSome:
      result = cmd.runCodeImpl.get()(args)
    else:
      callHook(cmd.runImpl, args)
  except CatchableError as e:
    failure = e
  var posts: seq[Option[Handler]] = @[cmd.postRunImpl]
  for i in countdown(path.len - 2, 0):
    posts.add path[i].persPostRunImpl
  for hook in posts:
    try:
      callHook(hook, args)
    except CatchableError as e:
      if failure.isNil:
        failure = e
  if not failure.isNil:
    raise failure

proc executeCode*(root: Command, tokens: seq[string] = commandLineParams()): int =
  ## Как `execute`, но возвращает код выхода int-обработчика (0, если
  ## обработчик без кода или его нет).
  ## Like `execute`, but returns the exit code of an int handler (0 when the
  ## handler has no code or there is none).
  let parsed = parse(root, tokens)
  checkCommand(parsed.path[^1], parsed.args)
  checkArgs(parsed.path[^1], parsed.args)
  runHooks(parsed)

proc execute*(root: Command, tokens: seq[string] = commandLineParams()) =
  ## Разбор, неизвестная команда, лимит, хуки. Ошибку CLI не печатает и
  ## процесс не завершает.
  ## Parse, unknown command, limit, hooks. Does not print a CLI error and
  ## does not exit the process.
  discard executeCode(root, tokens)

proc tryExecuteCode*(
    root: Command, tokens: seq[string] = commandLineParams()
): Result[int, ref CliError] =
  ## `tryExecute` с кодом выхода обработчика.
  ## `tryExecute` with the handler's exit code.
  try:
    ok(executeCode(root, tokens))
  except CliError as e:
    err(e)

proc tryExecute*(
    root: Command, tokens: seq[string] = commandLineParams()
): Result[void, ref CliError] =
  ## Ловит только `CliError`. Прочие исключения остаются сбоем программы.
  ## Catches only `CliError`. Other exceptions stay program failures.
  try:
    execute(root, tokens)
    ok()
  except CliError as e:
    err(e)

proc executeOrQuit*(
    root: Command, tokens: seq[string] = commandLineParams(), prefix = ""
) =
  ## Единственная точка `quit`. В тестах не вызывать.
  ## Ошибка CLI: `prefix` и текст в stderr, выход с `exitCode(err)`
  ## (ошибки использования — 2, остальные — 1, либо `err.code`).
  ## Успех: если int-обработчик вернул не 0, выход с этим кодом.
  ## The only `quit`. Do not call it from tests.
  ## A CLI error: `prefix` and the text on stderr, exit with `exitCode(err)`
  ## (usage errors 2, others 1, or `err.code`).
  ## Success: if an int handler returned non-zero, exit with that code.
  var code = 0
  try:
    code = executeCode(root, tokens)
  except CliError as e:
    e.gracefulHandle(prefix)
  if code != 0:
    quit code
