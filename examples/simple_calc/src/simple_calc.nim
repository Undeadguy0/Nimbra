import nimbra
from unicode import toUpper
import results
import unittest

type OperationType = enum 
  Add
  Div
  Min
  Mul


proc calc(operType: OperationType, args: seq[string]) = discard

when isMainModule:
  defineCommand(calc, mainCmd)