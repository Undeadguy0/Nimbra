![Nimbra-logo](Nimbra_logo.jpg)

# 🌐 Language / Язык
[🇺🇸 English](#english) | [🇷🇺 Русский](#russian)

---

<a name="english"></a>
# 🇺🇸 Nimbra

A library for building CLI applications in Nim, inspired by [Cobra](https://github.com/spf13/cobra) and [Cligen](https://github.com/c-blake/cligen).

## Overview

Key features of the library:

- Simple creation of nested (hierarchical) commands.
- POSIX-compliant argument parser.
- Command aliases.
- Support for two command declaration paradigms:
  1. **Cobra-like**: Explicit command and constructor declaration.
  2. **Cligen-like**: Declarative definition via function signatures using macros.
- Lifecycle hooks similar to Cobra (`PreCommand`, `PostCommand`), with support for "inheritance" via persistent hooks *(Beta: may be unstable)*.
- Support for two error-handling paradigms:
  1. Via exceptions.
  2. Via `Result` type return values.

## Fundamental Concepts

Everything is built upon three core classes: `Command`, `Flag`, and `ArgLimit`.

- **`Command`**: The base class for a command, capable of having child subcommands.
- **`Flag`**: Represents a command-line flag. Supports aliases for long names and can be inherited (persistent).
- **`ArgLimit`**: Defines constraints on the number of positional arguments.

## Roadmap

- [ ] Add support for using asynchronous (`async`) functions as executable commands.
- [ ] Add `{.aliases.}` pragma support for aliases when using `defineCommand`.
- [ ] Add automatic generation of the `--help` flag and its content without explicit declaration.
- [ ] Add shell autocompletion support for `zsh`, `fish`, `bash`, and `pwsh`.
- [ ] Add optional autocompletion support for `nushell`.

> *Note for contributors: When updating this README, please keep both English and Russian versions in sync.*

---

## Project Structure

```
clibra/
├── src/                    # Source code
│   ├── nimbra.nim          # Facade module: re-exports all public API
│   ├── commands/           # Core command engine
│   │   ├── command.nim     # Command tree, flag registration, argv parsing, hook execution
│   │   ├── flag.nim        # FlagSet: storage, lookup, and invocation of flags
│   │   └── arg_limits.nim  # ArgLimit type and constructors (noArgs, exact, atLeast, atMost, between)
│   ├── exceptions.nim      # CLI error hierarchy (CliError, ParsingFlagError, MissingFlagError, CliSettingError, ArgCountError)
│   ├── stdconv.nim         # Built-in fromString parsers for CliValue concept (int, uint, float, char, string, bool, enum, IpAddress)
│   └── definecmd.nim       # Cligen-like macro: defineCommand macro for declarative command definition
├── tests/                  # Test suite
│   ├── all_tests.nim       # Test runner
│   ├── test_values.nim     # fromString / CliValue tests
│   ├── test_parse.nim      # argv parsing tests
│   ├── test_hooks.nim      # Hook lifecycle tests
│   ├── test_define_command.nim  # defineCommand macro tests
│   └── test_flags.nim      # Flag registration and parsing tests
├── examples/               # Example applications
│   └── simple_calc/        # Simple calculator CLI example
├── nimbra.nimble           # Nimble package manifest
└── README.md               # This file
```

### src/ — Module Reference

| File | Responsibility |
|------|----------------|
| `nimbra.nim` | **Facade**. Exports `exceptions`, `stdconv`, `arg_limits`, `command`, `definecmd`. This is the single public import for users. |
| `commands/command.nim` | **Command engine**: `Command` ref object, `Parsed` result, `newCommand`, `add`, `addFlag` (3 overloads: scalar, `seq[T]`, `Option[T]`), `parse`, `execute`, `tryExecute`, `executeOrQuit`, hook setters (`setRun`, `setPreRun`, `setPostRun`, `setPersistentPreRun`, `setPersistentPostRun`), hook execution chain. |
| `commands/flag.nim` | **Flag storage**: `Flag` object, `FlagSet` with `seq[Flag]` + `byLong`/`byShort` index tables, `add`/`checkAdd`/`findLong`/`findShort`, `persistentFlags` extraction for inheritance. |
| `commands/arg_limits.nim` | **ArgLimit**: `min`/`max` bounds, constructors (`noArgs`, `exact`, `atLeast`, `atMost`, `between`), `holds` validator. |
| `exceptions.nim` | **Error hierarchy**: `CliError` (base), `ParsingFlagError` (flag + raw), `MissingFlagError` (flag), `CliSettingError` (flag), `ArgCountError` (got/min/max), constructors, `$` formatter, `gracefulHandle`, `toCliError` for Result interop. |
| `stdconv.nim` | **Built-in parsers**: `CliValue` concept (`fromString(typedesc[T], string)`), `argHint` for help, `fromString` overloads for `int`, `uint`, `float`, `char`, `string`, `bool`, enums, `IpAddress`. |
| `definecmd.nim` | **Cligen-like macro**: `defineCommand` macro transforms a procedure signature into command construction (`newCommand` + `addFlag` + `setRun`). Supports `short`/`help` pragmas, scalar/`seq`/`Option` parameters, `Result[void, E]` return for error handling. |

---

<a name="russian"></a>
# 🇷🇺 Nimbra

Библиотека для написания CLI-приложений на Nim, вдохновленная [Cobra](https://github.com/spf13/cobra) и [Cligen](https://github.com/c-blake/cligen).

## Обзор

Основные функции библиотеки:

- Простое создание вложенных (иерархических) команд.
- POSIX-совместимый парсер аргументов.
- Псевдонимы (aliases) для команд.
- Совмещение двух способов объявления команд:
  1. **Cobra-like**: явное объявление команд и конструкторов.
  2. **Cligen-like**: декларативное описание по сигнатуре функций через макросы.
- Функции-хуки с привязкой к жизненному циклу программы на манер Cobra (`PreCommand`, `PostCommand`) с возможностью "наследования" через persistent-версии *(Бета: может быть нестабильна)*.
- Поддержка двух парадигм обработки ошибок:
  1. Через исключения.
  2. Через возвращаемое значение с типом `Result`.

## Фундаментальные концепции

Всё базируется на трех основных классах: `Command`, `Flag` и `ArgLimit`.

- **`Command`**: базовый класс команды, поддерживающий дочерние элементы в виде подкоманд.
- **`Flag`**: репрезентация флага. Поддерживает псевдонимы для длинных имен и может быть наследуемым (persistent).
- **`ArgLimit`**: ограничение количества позиционных аргументов.

## Планы на будущее

- [ ] Добавить возможность использования асинхронных (`async`) функций как исполняемых команд.
- [ ] Добавить прагму `{.aliases.}` для псевдонимов при использовании `defineCommand`.
- [ ] Добавить автогенерацию флага `--help` и его содержимого без явного указания.
- [ ] Добавить поддержку автодополнения в `zsh`, `fish`, `bash` и `pwsh`.
- [ ] Добавить поддержку автодополнения в `nushell` (опционально).

> *Примечание для контрибьюторов: При обновлении этого файла, пожалуйста, синхронизируйте изменения в английской и русской версиях.*

---

## Структура проекта

```
clibra/
├── src/                    # Исходный код
│   ├── nimbra.nim          # Фасадный модуль: реэкспортирует весь публичный API
│   ├── commands/           # Ядро команд
│   │   ├── command.nim     # Дерево команд, регистрация флагов, разбор argv, запуск хуков
│   │   ├── flag.nim        # FlagSet: хранение, поиск и вызов флагов
│   │   └── arg_limits.nim  # Тип ArgLimit и конструкторы (noArgs, exact, atLeast, atMost, between)
│   ├── exceptions.nim      # Иерархия ошибок CLI (CliError, ParsingFlagError, MissingFlagError, CliSettingError, ArgCountError)
│   ├── stdconv.nim         # Встроенные парсеры fromString для концепта CliValue (int, uint, float, char, string, bool, enum, IpAddress)
│   └── definecmd.nim       # Макрос в стиле cligen: defineCommand для декларативного определения команд
├── tests/                  # Набор тестов
│   ├── all_tests.nim       # Запускатель тестов
│   ├── test_values.nim     # Тесты fromString / CliValue
│   ├── test_parse.nim      # Тесты разбора argv
│   ├── test_hooks.nim      # Тесты жизненного цикла хуков
│   ├── test_define_command.nim  # Тесты макроса defineCommand
│   └── test_flags.nim      # Тесты регистрации и разбора флагов
├── examples/               # Примеры приложений
│   └── simple_calc/        # Пример простого калькулятора CLI
├── nimbra.nimble           # Манифест пакета Nimble
└── README.md               # Этот файл
```

### src/ — Справочник модулей

| Файл | Ответственность |
|------|-----------------|
| `nimbra.nim` | **Фасад**. Экспортирует `exceptions`, `stdconv`, `arg_limits`, `command`, `definecmd`. Единая публичная точка входа для пользователей. |
| `commands/command.nim` | **Движок команд**: `Command` (ref object), `Parsed`, `newCommand`, `add`, `addFlag` (3 перегрузки: скаляр, `seq[T]`, `Option[T]`), `parse`, `execute`, `tryExecute`, `executeOrQuit`, сеттеры хуков (`setRun`, `setPreRun`, `setPostRun`, `setPersistentPreRun`, `setPersistentPostRun`), цепочка выполнения хуков. |
| `commands/flag.nim` | **Хранилище флагов**: объект `Flag`, `FlagSet` с `seq[Flag]` + индексные таблицы `byLong`/`byShort`, `add`/`checkAdd`/`findLong`/`findShort`, `persistentFlags` для наследования. |
| `commands/arg_limits.nim` | **ArgLimit**: границы `min`/`max`, конструкторы (`noArgs`, `exact`, `atLeast`, `atMost`, `between`), валидатор `holds`. |
| `exceptions.nim` | **Иерархия ошибок**: `CliError` (база), `ParsingFlagError` (флаг + raw), `MissingFlagError` (флаг), `CliSettingError` (флаг), `ArgCountError` (got/min/max), конструкторы, форматтер `$`, `gracefulHandle`, `toCliError` для работы с Result. |
| `stdconv.nim` | **Встроенные парсеры**: концепт `CliValue` (`fromString(typedesc[T], string)`), `argHint` для help, перегрузки `fromString` для `int`, `uint`, `float`, `char`, `string`, `bool`, перечисления, `IpAddress`. |
| `definecmd.nim` | **Макрос в стиле cligen**: `defineCommand` превращает сигнатуру процедуры в построение команды (`newCommand` + `addFlag` + `setRun`). Поддерживает прагмы `short`/`help`, параметры-скаляры/`seq`/`Option`, возврат `Result[void, E]` для обработки ошибок. |