# AGENTS.md

This repository is `du`, GNU du written in the Loup programming language, as
part of the loup-cmd series of example applications. It is a `host.native`
project: every source file is `.lphc`, the walk runs on OS threads, a
`unique class` owns each open directory descriptor, and libc is called
through `extern native`, so the program only runs as a native binary.

## Skills

| Skill | Location | Use it when |
|-------|----------|-------------|
| `loup-programmer` | [skills/loup-programmer/SKILL.md](skills/loup-programmer/SKILL.md) | Writing, reviewing, debugging or explaining Loup code: `.lpscr`, `.loup`, `.lphc`, `.lpweb` or `.lpfree` source files, `.lppkg` manifests, `@mode(...)` directives, or the `loup` / `loup-bootstrap` commands. |

Read `skills/loup-programmer/SKILL.md` before writing or changing any Loup code
in this repository. It links to detailed references under
`skills/loup-programmer/references/` for syntax, types and ownership
(`unique`, `edits`, `borrow`), execution modes and projects, errors and
diagnostics, the standard library, and common mistakes. Load those only as
needed.

## Code layout

```text
.
├── package.lppkg                # Loup manifest: name, version, toolchain, [build] entry, [test] pattern
├── Makefile                     # run, check, test, build, e2e, ci, clean
├── source/                      # all Loup code; modules import each other by path from here
│   ├── main.lphc                # entry point: func main() calls run(runtime.args())
│   ├── appinfo.lphc             # APP_NAME, APP_VERSION, exit statuses, thread limits
│   ├── cli/
│   │   ├── args.lphc            # class Options (@unsafe sendable), ArgError, parse_args()
│   │   ├── usage.lphc           # usage(), version_line()
│   │   └── app.lphc             # run(), run_with_env(): parse, help/version, unit from the environment
│   ├── size/
│   │   └── units.lphc           # parse_size(), BlockSize, block_size_from_env(), format_size(), human_size()
│   ├── fs/
│   │   └── files.lphc           # @repr(C) struct StatBuf, extern native libc, errno, FileInfo, unique class DirHandle
│   ├── walk/
│   │   ├── excludes.lphc        # Glob, excluded_path(), ExcludeList (Sendable, RwLock)
│   │   ├── ledger.lphc          # synchronized class Ledger, key_part(), child_key()
│   │   ├── visit.lphc           # class Visit, entry_path()
│   │   └── walker.lphc          # walk_operand(): Walker, JobQueue, Harvest, worker threads
│   ├── report/
│   │   ├── tree.lphc            # class Entry[lifetime ~tree] with unowned parent, build_tree()
│   │   └── report.lphc          # class Report: post-order sums, lines, grand total
│   └── commands/
│       └── du.lphc              # run_du(), load_excludes(), thread_count()
├── tests/
│   ├── *_test.lphc              # native unit tests: func test_*(): void
│   ├── helpers.lphc             # expect_text(), make_file(), make_hard_link(), make_symlink()
│   └── e2e.sh                   # end-to-end tests of the native binary
├── specs/du/                    # requirements.md, design.md, tasks.md
├── skills/loup-programmer/      # the Loup skill and its references
├── .github/workflows/ci.yml     # installs Loup and runs `make ci`
└── build/                       # build output (git-ignored)
```

## Build, run and test

Prerequisites: Linux x86-64 with glibc, Loup 1.26.0 (`loup` and
`loup-bootstrap` on `PATH`), `make`, and `clang` 17 or later.

Loup Lite comes from <https://github.com/code-craft-ai-company/loup-releases>;
[README.md](README.md#installing-loup-lite) has the install commands.

| Task | Command | Notes |
|------|---------|-------|
| Run | `make run ARGS="-sh /usr/share"` | builds `build/du`, then runs it: `loup run` cannot call libc |
| Type-check | `make check` | Stage0 checks `source/main.lphc` and every module it imports; tests are not checked |
| Run all tests | `make test` | every `tests/*_test.lphc`, each test built by Stage0 as a native binary (about 1.5 s each) |
| Run matching tests | `make test TEST_ARGS="--filter glob"` | tests whose name contains `glob` |
| Run one test file | `make test TEST_ARGS="--file tests/walker_test.lphc"` | |
| Build | `make build` | the self-hosted compiler (`loup build --target native`) writes `build/du` |
| End-to-end tests | `make e2e` | runs `tests/e2e.sh build/du` on scratch trees in a temporary directory |
| Everything CI runs | `make ci` | check, test, build, e2e, then `build/du --version` |
| Clean | `make clean` | removes `build/`, `.temp/` and `.loup-cache/` |

Run `make ci` before reporting a change as done.

Two native compilers are involved: the self-hosted one builds the binary,
Stage0 builds the unit tests (its test runner puts each host.native test
through its own native pipeline, in a temporary package outside the
repository; hence the absolute `LOUPPATH=$(CURDIR)/source:$(CURDIR)/tests`).
A change must compile and behave the same under both.

## Making a change

1. Update the spec in `specs/du/` (see [specs/README.md](specs/README.md)).
2. Change the code under `source/`.
3. Add or update unit tests in `tests/` and cases in `tests/e2e.sh`.
4. Run `make ci`.
5. Tick the finished tasks in `specs/du/tasks.md`.

Only `commands/du.lphc` and `cli/app.lphc` print. Worker threads never
print or touch shared state outside the synchronized classes and the
read-locked exclude list; keep it that way, or the output stops being the
same for every `-j`.

## Conventions

- Every source file is `@mode(host.native)` with the `.lphc` extension. Only
  `source/main.lphc` has a `main()`.
- Modules import each other by path from `source/`:
  `from walk.ledger import (Ledger);`. Tests import them the same way. Do not
  use relative imports.
- Records that cross modules are classes, not structs: the native back ends
  place struct fields by name across the whole program. The only structs
  are the `@repr(C)` buffers in `fs/files.lphc`, whose `st_`-prefixed field
  names no other type may use.
- Loup 1.26.0 native-lane pitfalls this code works around:
  - `match` on a `string` always takes the `_` arm in Stage0 native code:
    use `if (s == "x") ... else if` chains (see `apply` in `cli/args.lphc`).
  - RwLock methods are not lowered on a field (Stage0), and guard methods
    are not lowered on a guard another function returned (self-hosted):
    lock, use and release inside one helper that receives the lock
    (`walk/excludes.lphc`).
  - The self-hosted checker wants `safe { }` around calls of a
    `synchronized class`'s modifier methods; Stage0 does not.
  - `expectEq` on two equal strings fails in native tests: use
    `expect_text(actual, expected, context)` from `tests/helpers.lphc`.
  - A test file that does not compile (a reserved word such as `from` or
    `where` as a name is enough) is skipped silently. A full `make test`
    therefore fails unless it ran every `test_` function; find the broken
    file with `LOUPPATH=source:tests loup-bootstrap run tests/FILE`.
- Keep `APP_VERSION` in `source/appinfo.lphc` equal to `version` in
  `package.lppkg`.
- The skill documents toolchain 1.25.1; this project targets 1.26.0. When
  they disagree, trust the toolchain's behaviour.
