## Автоматические -h/--help и -V/--version, текст help.
## Automatic -h/--help and -V/--version, help text.
##
## Тексты сверяются побайтово. / Texts are compared byte for byte.

import std/options
import std/os
import std/osproc
import std/streams
import std/strutils
import std/unittest
import results
import nimbra

const root = currentSourcePath().parentDir.parentDir

type Mode = enum
  Fast
  Slow

proc lines(ls: openArray[string]): string =
  ls.join("\n") & "\n"

var
  only: seq[string]
  dry = false
  port = 0
  who = ""
  mode = Fast

proc sample(): Command =
  let
    theme = newCommand("theme", help = "switch desktop appearance presets")
    list = newCommand("list", help = "list presets", aliases = @["ls"])
    setc = newCommand("set", help = "activate a preset")
    serve = newCommand("serve", help = "start the server")
  theme.version = "0.3.0"
  theme.epilog = "Exit codes: 0 ok, 1 failure, 2 usage error"
  setc.argsHint = "<preset>"
  setc.addFlag("only", only, sep = some(','), help = "comma-separated parts")
  setc.addFlag("dry-run", dry, short = some('n'), help = "print what would happen")
  serve.addFlag("port", port, short = some('p'), aliases = @["listen"],
                default = some(8080), help = "port to listen on")
  serve.addFlag("name", who, required = true, help = "who")
  serve.addFlag("mode", mode)
  theme.add list
  theme.add setc
  theme.add serve
  theme

const
  rootHelp = @[
    "switch desktop appearance presets",
    "",
    "Usage:",
    "  theme <command> [flags]",
    "",
    "Commands:",
    "  list, ls  list presets",
    "  set       activate a preset",
    "  serve     start the server",
    "",
    "Flags:",
    "  -h, --help     show this help",
    "  -V, --version  print version",
    "",
    "Exit codes: 0 ok, 1 failure, 2 usage error",
  ].join("\n") & "\n"
  setHelp = @[
    "activate a preset",
    "",
    "Usage:",
    "  theme set [flags] <preset>",
    "",
    "Flags:",
    "      --only <string,...>  comma-separated parts",
    "  -n, --dry-run            print what would happen",
    "  -h, --help               show this help",
  ].join("\n") & "\n"
  serveHelp = @[
    "start the server",
    "",
    "Usage:",
    "  theme serve [flags]",
    "",
    "Flags:",
    "  -p, --port, --listen <int>  port to listen on (default: 8080)",
    "      --name <string>         who (required)",
    "      --mode <Fast|Slow>",
    "  -h, --help                  show this help",
  ].join("\n") & "\n"
  bareHelp = @[
    "Usage:",
    "  tool [flags]",
    "",
    "Flags:",
    "  -h, --help  show this help",
  ].join("\n") & "\n"

suite "help text":
  test "root: commands with aliases, auto flags, epilog":
    check sample().helpText() == rootHelp

  test "subcommand: args hint, separator hint, no version line":
    check sample().helpText(@["set"]) == setHelp

  test "aliases, default, required and enum hint":
    check sample().helpText(@["serve"]) == serveHelp

  test "no help text, no version, no epilog":
    check newCommand("tool").helpText() == bareHelp

  test "helpText by alias, unknown name raises":
    check sample().helpText(@["ls"]).startsWith("list presets\n")
    expect CliError:
      discard sample().helpText(@["nope"])

  test "own help or h flag is not shadowed":
    var help = false
    var h = 0
    let cmd = newCommand("app")
    cmd.addFlag("help", help)
    cmd.addFlag("hh", h, short = some('h'))
    check cmd.helpText() == lines([
      "Usage:", "  app [flags]", "", "Flags:",
      "      --help", "  -h, --hh <int>",
    ])
    check cmd.parse(@["--help", "-h", "3"]).help == false
    check help
    check h == 3

suite "help request":
  test "flags anywhere, no callbacks, no required check, no hooks":
    var ran = false
    let theme = sample()
    theme.setPersistentPreRun proc(args: seq[string]) =
      ran = true
    for argv in [@["--help"], @["-h"], @["serve", "--help"], @["serve", "-h", "--name"],
                 @["serve", "x", "-h"], @["serve", "--mode", "Bogus", "-h"],
                 @["serve", "--nope", "--help"]]:
      let parsed = theme.parse(argv)
      check parsed.help
    check theme.tryExecute(@["serve", "--help"]).isOk
    check ran == false
    check who == ""
    let path = theme.parse(@["serve", "-h"]).path
    check path[^1].name == "serve"
    check theme.parse(@["--help"]).path.len == 1

  test "after -- and as a flag value they are plain":
    var name = ""
    let cmd = newCommand("app")
    cmd.addFlag("name", name)
    let after = cmd.parse(@["--", "-h", "--help"])
    check after.help == false
    check after.args == @["-h", "--help"]
    let value = cmd.parse(@["--name", "-h"])
    check value.help == false
    check name == "-h"

  test "version only on a root with version set":
    let theme = sample()
    check theme.parse(@["-V"]).version
    check theme.parse(@["--version"]).version
    check theme.versionText() == "theme 0.3.0\n"
    check theme.parse(@["serve", "--version"]).version == false
    check theme.tryExecute(@["serve", "-V"]).error of ParsingFlagError
    let plain = newCommand("app")
    check plain.parse(@["x"]).version == false
    check plain.tryExecute(@["-V"]).error of ParsingFlagError
    check newCommand("app").versionText() == ""

  test "help wins over version, version skips flag parsing":
    let theme = sample()
    let both = theme.parse(@["-V", "-h"])
    check both.help
    check both.version == false

  test "bare parent without run shows help, others do not":
    let theme = sample()
    check theme.parse(@[]).help == false
    check theme.wantsHelp(theme.parse(@[]))
    theme.setRun proc(args: seq[string]) = discard
    check not theme.wantsHelp(theme.parse(@[]))
    let leaf = newCommand("leaf")
    check not leaf.wantsHelp(leaf.parse(@[]))
    let parent = newCommand("p")
    parent.add newCommand("c")
    check not parent.wantsHelp(parent.parse(@["x"]))

suite "flag hints":
  test "argHint for enum lists the values":
    check argHint(Mode) == "Fast|Slow"

proc buildDemo(): string =
  let
    outDir = getTempDir() / "nimbra-exit"
    bin = outDir / "exit_demo_app"
  createDir(outDir)
  let cmd = quoteShellCommand([
    getCurrentCompilerExe(), "c", "--hints:off", "--verbosity:0",
    "--path:" & (root / "src"), "--nimcache:" & (outDir / "cache-help"),
    "-o:" & bin, root / "tests" / "exit_demo_app.nim",
  ])
  let (output, code) = execCmdEx(cmd)
  if code != 0:
    echo output
  doAssert code == 0
  bin

proc runDemo(bin: string, args: openArray[string]): tuple[stdout, stderr: string, code: int] =
  let p = startProcess(bin, args = args, options = {})
  let o = p.outputStream.readAll()
  let e = p.errorStream.readAll()
  let c = p.waitForExit()
  p.close()
  (o, e, c)

suite "help in a process":
  let bin = buildDemo()
  const demoHelp = lines([
    "demo application", "",
    "Usage:", "  demo <command> [flags]", "",
    "Commands:",
    "  boom  fail with code 3",
    "  code  exit with code 4",
    "  need  needs a flag",
    "  fine  print fine", "",
    "Flags:",
    "  -h, --help     show this help",
    "  -V, --version  print version", "",
    "Run `demo <command> --help` for details.",
  ])

  test "--help prints to stdout and exits 0":
    for flag in ["--help", "-h"]:
      let r = runDemo(bin, [flag])
      check r.code == 0
      check r.stdout == demoHelp
      check r.stderr == ""

  test "bare root shows help":
    let r = runDemo(bin, [])
    check r.code == 0
    check r.stdout == demoHelp

  test "subcommand help beats the required flag":
    let r = runDemo(bin, ["need", "--help"])
    check r.code == 0
    check r.stdout == lines([
      "needs a flag", "",
      "Usage:", "  demo need [flags]", "",
      "Flags:",
      "  -n, --n <int>  (required)",
      "  -h, --help     show this help",
    ])

  test "version":
    let r = runDemo(bin, ["--version"])
    check r.code == 0
    check r.stdout == "demo 1.2.3\n"
    check runDemo(bin, ["-V"]).stdout == "demo 1.2.3\n"
