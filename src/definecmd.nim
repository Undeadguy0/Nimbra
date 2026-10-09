## Сахар cligen: из сигнатуры процедуры собирает ту же команду, что пишут руками.
##
## Разворот вставляет `var` в область вызова. `execute` вызывают там же,
## иначе адрес переменной не доживёт до запуска.
##
## Дефолт параметра `Option[T]` уже имеет тип `Option` и уходит в `addFlag`
## как есть. У скаляра и `seq` он оборачивается в `some`.
## Возврат `Result[void, E]` садится в result-перегрузку `setRun`.
## Любой другой возврат вызывается из обычного обработчика.
##
## Cligen-style sugar: a procedure signature becomes the same command written by hand.
##
## Expansion inserts `var`s at the call site. Call `execute` there too,
## or the variable's address will not survive until launch.
##
## A default on an `Option[T]` parameter is already an `Option` and is passed
## to `addFlag` as is. A scalar or `seq` default is wrapped in `some`.
## A `Result[void, E]` return uses the Result overload of `setRun`.
## Any other return is called from an ordinary handler.

import std/macros
import std/options

template short*(value: char) {.pragma.}
  ## Короткое имя флага у параметра `defineCommand`.
  ## Short flag name on a `defineCommand` parameter.

template help*(text: string) {.pragma.}
  ## Текст help у параметра или у самой процедуры `defineCommand`.
  ## Help text on a parameter or on the `defineCommand` procedure itself.

type ParamInfo = object
  name: string
  typ: NimNode
  defaultNode: NimNode
  shortNode: NimNode
  help: string
  positional: bool
  isBool: bool

proc isBoolType(t: NimNode): bool =
  t.eqIdent("bool")

proc isPositionalArgs(name: string, t: NimNode): bool =
  ## Позиционные — только параметр `args: seq[string]`.
  ## У типизированной процедуры тип часто остаётся `BracketExpr`,
  ## но иногда `repr` уже показывает `seq[string]`.
  ## Positionals are only the parameter `args: seq[string]`.
  ## On a typed procedure the type often stays a `BracketExpr`,
  ## but sometimes `repr` already shows `seq[string]`.
  if name != "args":
    return false
  if t.kind == nnkBracketExpr and t.len >= 2 and t[0].eqIdent("seq") and
      t[^1].eqIdent("string"):
    return true
  let text = t.repr
  text == "seq[string]" or (text.len >= 11 and text[^11 .. ^1] == "seq[string]")

proc bare(n: NimNode): NimNode =
  if n.kind == nnkPostfix:
    n[1]
  else:
    n

proc nodeText(n: NimNode): string =
  let b = bare(n)
  if b.kind in {nnkIdent, nnkSym, nnkAccQuoted}:
    $b
  else:
    b.strVal

proc applyPragma(p: NimNode, info: var ParamInfo) =
  let (key, val) =
    if p.kind == nnkExprColonExpr and p.len == 2:
      (p[0], p[1])
    elif p.kind == nnkCall and p.len == 2:
      (p[0], p[1])
    else:
      return
  if key.eqIdent("short"):
    info.shortNode = val
  elif key.eqIdent("help") and val.kind in {nnkStrLit, nnkTripleStrLit, nnkRStrLit}:
    info.help = val.strVal

proc readPragmas(prag: NimNode, info: var ParamInfo) =
  if prag.kind != nnkPragma:
    return
  for p in prag:
    applyPragma(p, info)

proc takeName(n: NimNode, info: var ParamInfo) =
  if n.kind == nnkPragmaExpr:
    takeName(n[0], info)
    readPragmas(n[1], info)
  elif n.kind in {nnkIdent, nnkSym, nnkAccQuoted}:
    info.name = $n
  else:
    error("unsupported parameter name", n)

proc collectParams(params: NimNode): seq[ParamInfo] =
  for i in 1 ..< params.len:
    let id = params[i]
    expectKind(id, nnkIdentDefs)
    let typ = id[^2]
    let defNode = id[^1]
    for n in 0 ..< id.len - 2:
      var info = ParamInfo(typ: typ, defaultNode: defNode, shortNode: newEmptyNode())
      takeName(id[n], info)
      info.positional = isPositionalArgs(info.name, typ)
      info.isBool = isBoolType(typ)
      result.add info

proc routineHelp(pragmas: NimNode): string =
  if pragmas.kind != nnkPragma:
    return
  for p in pragmas:
    if p.kind == nnkExprColonExpr and p.len == 2 and p[0].eqIdent("help"):
      return p[1].strVal
    if p.kind == nnkCall and p.len == 2 and p[0].eqIdent("help"):
      return p[1].strVal

proc named(name: string, value: NimNode): NimNode =
  newTree(nnkExprEqExpr, ident(name), value)

proc typeHead(t: NimNode): string =
  if t.kind == nnkBracketExpr and t.len >= 1:
    nodeText(t[0])
  elif t.kind in {nnkIdent, nnkSym, nnkAccQuoted}:
    nodeText(t)
  else:
    ""

proc isOptionType(t: NimNode): bool =
  typeHead(t) == "Option"

proc isVoidResult(t: NimNode): bool =
  ## Только `Result[void, E]` совпадает с result-перегрузкой `setRun`.
  ## Only `Result[void, E]` matches the Result overload of `setRun`.
  t.kind == nnkBracketExpr and typeHead(t) == "Result" and t.len >= 2 and
    (t[1].kind == nnkEmpty or t[1].eqIdent("void"))



macro defineCommand*(fn: typed, dest: untyped): untyped =
  ## Декларативно конквертирует функцию-обработчик в Command.
  ## Первый аргумент - обработчик, второй - имя будущей Command
  let impl = fn.getImpl()
  if impl.kind notin {nnkProcDef, nnkFuncDef, nnkLambda}:
    error("defineCommand expects a procedure", fn)
  if impl.kind != nnkLambda and impl[2].kind != nnkEmpty:
    error("defineCommand supports concrete procedures only", fn)

  let paramsNode =
    if impl.kind == nnkLambda:
      impl[3]
    else:
      impl[3]
  let ret = paramsNode[0]
  let helpText =
    if impl.kind == nnkLambda:
      ""
    else:
      routineHelp(impl[4])
  let fnName =
    if impl.kind == nnkLambda:
      "command"
    else:
      nodeText(impl[0])
  let params = collectParams(paramsNode)
  let someSym = bindSym("some")
  let newCommandId = ident("newCommand")
  let addFlagId = ident("addFlag")
  let setRunId = ident("setRun")
  result = newStmtList()

  var slots: seq[tuple[sym: NimNode, positional: bool]]
  for p in params:
    if p.positional:
      slots.add (genSym(nskParam, "args"), true)
      continue
    let sym = genSym(nskVar, p.name)
    slots.add (sym, false)
    let typNode = p.typ.copyNimTree()
    if p.defaultNode.kind == nnkEmpty:
      result.add quote do:
        var `sym`: `typNode`
    else:
      let init = p.defaultNode.copyNimTree()
      result.add quote do:
        var `sym`: `typNode` = `init`

  let
    nameLit = newLit(fnName)
    helpLit = newLit(helpText)
  result.add quote do:
    var `dest` = `newCommandId`(`nameLit`, `helpLit`)

  for i, p in params:
    if p.positional:
      continue
    let sym = slots[i].sym
    var call = newCall(addFlagId, dest.copyNimTree(), newLit(p.name), sym)
    if p.defaultNode.kind != nnkEmpty:
      let defExpr =
        if isOptionType(p.typ):
          p.defaultNode.copyNimTree()
        else:
          newCall(someSym, p.defaultNode.copyNimTree())
      call.add named("default", defExpr)
    elif not p.isBool:
      call.add named("required", newLit(true))
    if p.shortNode.kind != nnkEmpty:
      call.add named("short", newCall(someSym, p.shortNode.copyNimTree()))
    if p.help.len > 0:
      call.add named("help", newLit(p.help))
    result.add call

  var invocation = newCall(fn)
  let argsSym = genSym(nskParam, "args")
  for i, p in params:
    if p.positional:
      invocation.add argsSym
    else:
      invocation.add slots[i].sym
  let retNode = ret.copyNimTree()
  if isVoidResult(ret):
    result.add quote do:
      `dest`.`setRunId`(
        proc(`argsSym`: seq[string]): `retNode` =
          `invocation`
      )
  elif ret.kind == nnkEmpty:
    result.add quote do:
      `dest`.`setRunId`(
        proc(`argsSym`: seq[string]) =
          `invocation`
      )
  else:
    result.add quote do:
      `dest`.`setRunId`(
        proc(`argsSym`: seq[string]) =
          discard `invocation`
      )
