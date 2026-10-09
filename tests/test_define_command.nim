import std/options
import std/unittest
import results
import nimbra

var
  seenPort = 0
  seenVerbose = false
  seenTags: seq[string]
  seenHost = ""

proc greet(name: string, times: int = 2, loud: bool, args: seq[string]) =
  check name == "ann"
  check times == 2
  check loud
  check args == @["x"]

proc greetR(name: string): Result[void, string] =
  if name == "bad":
    return err("nope")
  ok()

proc tagged(
    port {.short: 'p', help: "listen".}: int = 8080, args: seq[string]
) {.help: "serve files".} =
  seenPort = port
  check args.len == 0

proc prefer(verbose: bool = true) =
  seenVerbose = verbose

proc collect(tags: seq[string], host: Option[string], args: seq[string]) =
  seenTags = tags
  if host.isSome:
    seenHost = host.get
  else:
    seenHost = "none"

var
  loudSeen = true
  hostSeen = ""
  answerHit = 0
  midLeft = ""
  midArgs: seq[string]
  midRight = 0
  tagsDefault: seq[string]
  numsSeen: seq[int]

proc justLoud(loud: bool) =
  loudSeen = loud

proc shout(loud {.short: 'l'.}: bool) =
  loudSeen = loud

proc withHost(host: Option[string] = some("localhost")) =
  hostSeen = if host.isSome: host.get else: "none"

proc answer(name: string): int =
  answerHit = 7
  42

proc between(left: string, args: seq[string], right: int) =
  midLeft = left
  midArgs = args
  midRight = right

proc tagsDef(tags: seq[string] = @["d"]) =
  tagsDefault = tags

proc nums(ns: seq[int]) =
  numsSeen = ns

suite "defineCommand":
  test "flags, default, bool and required name":
    defineCommand(greet, app)
    check app.name == "greet"
    check app.tryExecute(@["--name", "ann", "--loud", "x"]).isOk
    check app.tryExecute(@["--loud"]).error of MissingFlagError

  test "procedure with Result":
    defineCommand(greetR, appR)
    check appR.tryExecute(@["--name", "a"]).isOk
    check appR.tryExecute(@["--name", "bad"]).error.msg == "nope"

  test "pragma short and help, default in signature":
    defineCommand(tagged, srv)
    check srv.help == "serve files"
    check srv.tryExecute(@["-p", "9"]).isOk
    check seenPort == 9
    check srv.tryExecute(@[]).isOk
    check seenPort == 8080

  test "bool with default and seq repeat":
    defineCommand(prefer, tool)
    check tool.tryExecute(@[]).isOk
    check seenVerbose
    check tool.tryExecute(@["--verbose=false"]).isOk
    check seenVerbose == false

    defineCommand(collect, box)
    check box.tryExecute(@["--tags", "a", "--tags", "b", "--host", "h"]).isOk
    check seenTags == @["a", "b"]
    check seenHost == "h"
    let missingHost = box.tryExecute(@["--tags", "a"])
    check missingHost.isOk
    check seenHost == "none"

  test "bool without default, Option with default, seq and int return":
    defineCommand(justLoud, loudCmd)
    check loudCmd.tryExecute(@[]).isOk
    check loudSeen == false
    check loudCmd.tryExecute(@["--loud"]).isOk
    check loudSeen
    check loudCmd.tryExecute(@["--loud=no"]).isOk
    check loudSeen == false

    defineCommand(shout, shoutCmd)
    check shoutCmd.tryExecute(@["-l"]).isOk
    check loudSeen

    defineCommand(withHost, hostCmd)
    check hostCmd.tryExecute(@[]).isOk
    check hostSeen == "localhost"
    check hostCmd.tryExecute(@["--host="]).isOk
    check hostSeen == "localhost"
    check hostCmd.tryExecute(@["--host", "box"]).isOk
    check hostSeen == "box"

    defineCommand(tagsDef, tagsCmd)
    check tagsCmd.tryExecute(@[]).isOk
    check tagsDefault == @["d"]

    defineCommand(nums, numsCmd)
    check numsCmd.tryExecute(@["--ns", "1", "--ns", "2"]).isOk
    check numsSeen == @[1, 2]
    check numsCmd.tryExecute(@[]).error of MissingFlagError

    defineCommand(answer, answerCmd)
    check answerCmd.tryExecute(@["--name", "a"]).isOk
    check answerHit == 7
    check answerCmd.tryExecute(@[]).error of MissingFlagError

    defineCommand(between, midCmd)
    check midCmd.tryExecute(@["--left", "L", "--right", "3", "p"]).isOk
    check midLeft == "L"
    check midArgs == @["p"]
    check midRight == 3
