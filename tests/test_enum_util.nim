import unittest
import ../src/stdconv
import macros

suite "ToEnum macro":
  setup:
    type 
        A = enum
            X
            Y
            Z

  test "Base usage":
    check A.X == A.toEnum("X")
    check A.Y == A.toEnum("Y")
    check A.Z == A.toEnum("Z")

    try:
      discard A.toEnum("W")
      check false
    except ValueError:
      check true
    except Exception:
      check false

    
