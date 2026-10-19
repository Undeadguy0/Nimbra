# Package

version = "0.2.0"
author = "Undeadguy"
description = "A CLI framework inspired by Go-Cobra"
license = "MIT"
srcDir = "src"

# Dependencies

requires "nim >= 2.2.10"
requires "results"

task test, "Run the test suite":
  exec "nim c -r --hints:off --nimcache:/tmp/nimbra-nimcache -o:/tmp/nimbra-tests tests/all_tests.nim"

task examples, "Build the examples":
  exec "nim c --hints:off --nimcache:/tmp/nimbra-nimcache-examples -o:/tmp/simple_calc examples/simple_calc/src/simple_calc.nim"
