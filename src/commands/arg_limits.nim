from options import Option, isNone, get
type
  ArgLimitKind* = enum
    alkNone
    alkLessThan
    alkLessOrEq
    alkGreaterThan
    alkGreaterOrEq
    alkEq
    alkBetween

  ArgLimit* = object
    case kind*: ArgLimitKind
    of alkNone:
      discard
    of alkLessThan:
      lessThan*: uint
    of alkLessOrEq:
      lessOrEq*: uint
    of alkGreaterThan:
      greaterThan*: uint
    of alkGreaterOrEq:
      greaterOrEq*: uint
    of alkEq:
      eq*: uint
    of alkBetween:
      min*, max*: uint

proc NoArgs*(): ArgLimit =
  return ArgLimit(kind: ArgLimitKind.alkNone)

proc LessThan*(border: uint): ArgLimit =
  return ArgLimit(kind: ArgLimitKind.alkLessThan, lessThan: border)

proc LessOrEq*(upTo: uint): ArgLimit =
  return ArgLimit(kind: ArgLimitKind.alkLessOrEq, lessOrEq: upTo)

proc GreaterThan*(start: uint): ArgLimit =
  return ArgLimit(kind: ArgLimitKind.alkGreaterThan, greaterThan: start)

proc GreaterOrEq*(start: uint): ArgLimit =
  return ArgLimit(kind: ArgLimitKind.alkGreaterOrEq, greaterOrEq: start)

proc Equal*(number: uint): ArgLimit =
  return ArgLimit(kind: ArgLimitKind.alkEq, eq: number)

proc Between*(start, to: uint): ArgLimit =
  return ArgLimit(kind: ArgLimitKind.alkBetween, min: start, max: to)

proc Matches*(o: Option[ArgLimit], args: seq[string]): bool =
  if o.isNone:
    return true

  let argsCount = uint(args.len)
  let val = o.get
  case val.kind
  of ArgLimitKind.alkNone:
    return argsCount == 0
  of ArgLimitKind.alkLessThan:
    return argsCount < val.lessThan
  of ArgLimitKind.alkLessOrEq:
    return argsCount <= val.lessOrEq
  of ArgLimitKind.alkGreaterThan:
    return argsCount > val.greaterThan
  of ArgLimitKind.alkGreaterOrEq:
    return argsCount >= val.greaterOrEq
  of ArgLimitKind.alkEq:
    return argsCount == val.eq
  of ArgLimitKind.alkBetween:
    return val.min <= argsCount and argsCount <= val.max
