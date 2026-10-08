## Сколько позиционных принимает команда.
##
## Верхней границы нет, когда `max.isNone`. Отдельного `Option[ArgLimit]`
## нет: «любое число» — это `min == 0` и пустой `max`.
##
## How many positionals a command accepts.
##
## There is no upper bound when `max.isNone`. There is no `Option[ArgLimit]`:
## "any count" is `min == 0` and an empty `max`.

import std/options
from ../exceptions import newCliSettingError

type ArgLimit* = object
  min*: uint
  max*: Option[uint]

proc noArgs*(): ArgLimit =
  ArgLimit(min: 0, max: some(0'u))

proc exact*(n: uint): ArgLimit =
  ArgLimit(min: n, max: some(n))

proc atLeast*(n: uint): ArgLimit =
  ArgLimit(min: n, max: none(uint))

proc atMost*(n: uint): ArgLimit =
  ArgLimit(min: 0, max: some(n))

proc between*(start, to: uint): ArgLimit =
  if start > to:
    raise newCliSettingError("argument range min is greater than max")
  ArgLimit(min: start, max: some(to))

proc holds*(limit: ArgLimit, count: int): bool =
  ## `count` — длина хвоста позиционных после разбора.
  ## `count` is the length of the positional tail after parsing.
  let n = uint(count)
  if n < limit.min:
    return false
  if limit.max.isSome and n > limit.max.get:
    return false
  true
