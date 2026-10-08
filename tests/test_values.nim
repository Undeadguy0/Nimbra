import std/math
import std/net
import std/options
import std/unittest
import results
import nimbra

type
  Color = enum
    red
    green

  Port = distinct int

proc fromString(_: typedesc[Port], r: string): Port =
  Port(fromString(int, r))

suite "fromString и argHint":
  test "числа съедают всю строку":
    check fromString(int, "12") == 12
    check fromString(int, "-3") == -3
    check fromString(int, "+3") == 3
    check fromString(int, "1_000") == 1000
    check fromString(uint, "4") == 4'u
    check fromString(uint, "+3") == 3'u
    check fromString(float, "1.5") == 1.5
    check fromString(float, ".5") == 0.5
    check fromString(float, "1.") == 1.0
    check fromString(float, "1e2") == 100.0
    check fromString(float, "inf") == Inf
    check fromString(float, "nan").isNaN
    expect ParsingFlagError:
      discard fromString(int, "12abc")
    expect ParsingFlagError:
      discard fromString(int, "")
    expect ParsingFlagError:
      discard fromString(int, "+")
    expect ParsingFlagError:
      discard fromString(int, "-")
    expect ParsingFlagError:
      discard fromString(int, "999999999999999999999999")
    expect ParsingFlagError:
      discard fromString(uint, "-1")
    expect ParsingFlagError:
      discard fromString(uint, "")
    expect ParsingFlagError:
      discard fromString(uint, "-0")
    expect ParsingFlagError:
      discard fromString(float, "")
    expect ParsingFlagError:
      discard fromString(float, "1.5x")
    expect ParsingFlagError:
      discard fromString(float, "+")

  test "fromString не знает имя флага":
    try:
      discard fromString(int, "nope")
      check false
    except ParsingFlagError as e:
      check e.flag == ""
      check e.raw == "nope"

  test "строка и символ":
    check fromString(string, "") == ""
    check fromString(string, "ab") == "ab"
    check fromString(char, "q") == 'q'
    expect ParsingFlagError:
      discard fromString(char, "ab")

  test "bool только известные слова":
    check fromString(bool, "YES")
    check fromString(bool, "off") == false
    check fromString(bool, "0") == false
    expect ParsingFlagError:
      discard fromString(bool, "")
    expect ParsingFlagError:
      discard fromString(bool, "maybe")

  test "enum и ip прячут ValueError":
    check fromString(Color, "red") == red
    check $fromString(IpAddress, "127.0.0.1") == "127.0.0.1"
    expect ParsingFlagError:
      discard fromString(Color, "blue")
    expect ParsingFlagError:
      discard fromString(IpAddress, "not-an-ip")

  test "argHint не входит в концепт":
    check argHint(int) == "int"
    check argHint(IpAddress) == "ip"
    check argHint(Port) == "value"

  test "свой тип подключается перегрузкой fromString":
    var port: Port
    let root = newCommand("app")
    root.addFlag("port", port, required = true)
    check root.tryExecute(@["--port", "80"]).isOk
    check int(port) == 80

  test "enum, символ и ip доходят через argv":
    var
      color = red
      mark = 'x'
      host = fromString(IpAddress, "127.0.0.1")
    let root = newCommand("app")
    root.addFlag("color", color, required = true)
    root.addFlag("mark", mark, required = true)
    root.addFlag("host", host, required = true)
    check root.tryExecute(@["--color", "green", "--mark", "q", "--host", "10.0.0.2"]).isOk
    check color == green
    check mark == 'q'
    check $host == "10.0.0.2"
    let bad =
      root.tryExecute(@["--color", "green", "--mark", "ab", "--host", "10.0.0.2"])
    check bad.error of ParsingFlagError
    check (ref ParsingFlagError)(bad.error).flag == "mark"
    check (ref ParsingFlagError)(bad.error).raw == "ab"

suite "текст ошибок":
  test "поля потомка читаются через $":
    var port = 0
    let root = newCommand("app")
    root.addFlag("port", port, required = true)
    root.argLimit = exact(2)
    let missing = root.tryExecute(@[])
    check $missing.error == "Missing required flag --port: flag not present"
    let bad = root.tryExecute(@["--port", "12abc", "a", "b"])
    check $bad.error == "Error parsing flag --port from '12abc': not an int"
    check root.tryExecute(@["--port", "1"]).error.msg ==
      "expected exactly 2 positional arguments, got 0"
    try:
      root.addFlag("port", port, default = some(1), required = true)
      check false
    except CliSettingError as e:
      check $e ==
        "Error while setting up flag --port: flag cannot be both required and have a default"
    try:
      newCommand("app").add(newCommand(""))
      check false
    except CliSettingError as e:
      check $e == "Error while CLI setup: command without name"
    check $toCliError("hello") == "hello"
