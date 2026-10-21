# Design: du

## Overview

`main()` hands `runtime.args()` to `cli.app.run`, which parses the options
into an `Options` object and calls `commands.du.run_du`. For each operand
in order, `walk.walker.walk_operand` stats the operand, lists its top-level
entries on the main thread and gives each top-level subdirectory to a pool
of worker threads as a job. A worker walks its job depth-first in sorted
name order and records every entry as a `Visit` (name, depth, size, inode,
walk key, error) in a list it hands back through a `synchronized class`.
After the workers are joined, `report.tree` grafts the visits into a tree
of `Entry` objects with `unowned` parent links, and `report.report` prints
it in post-order. All sources are `@mode(host.native)` `.lphc` files.

## Lanes

The binary is built by the self-hosted compiler (`loup build --target
native`); the unit tests are built by Stage0's native test runner
(`loup-bootstrap test --native`), and `make check` is Stage0's checker. The
code therefore keeps to what both native back ends compile the same way:
no `match` on strings (Stage0 native always takes `_`); an `RwLock` is
locked, used and released inside one helper that receives it as a
parameter (Stage0 refuses lock methods on a field, the self-hosted back end
guard methods on a returned guard); `safe { }` around calls of a
synchronized class's modifier methods (the self-hosted checker wants it);
no custom exception thrown across modules; records that cross modules are
classes; `@repr(C)` struct fields with names no other type uses.

## Modules

| Module | Contents |
|---|---|
| `source/main.lphc` | entry point: `run(runtime.args())` |
| `source/appinfo.lphc` | name, version, exit statuses, thread limits |
| `source/cli/args.lphc` | `Options` (`@unsafe("sendable: ...")`), `ArgError`, `parse_args`: getopt-style bundling, long-option prefixes |
| `source/cli/usage.lphc` | `usage()`, `version_line()` |
| `source/cli/app.lphc` | `run()`: parse, help/version, usage errors, `run_du` |
| `source/size/units.lphc` | `parse_size`, `BlockSize`, `block_size_from_env`, `format_size` (units, `-h`, `--si`) |
| `source/fs/files.lphc` | `@repr(C) struct StatBuf`, `extern native` `lstat`/`stat`/`fstatat`/`open`/`close`, `errno`, `FileInfo`, `unique class DirHandle` |
| `source/walk/excludes.lphc` | `glob_match`, `excluded_path`, `ExcludeList` (`Sendable`, `RwLock`) |
| `source/walk/ledger.lphc` | `synchronized class Ledger`: seen-inode claims, error and entry totals; walk keys |
| `source/walk/visit.lphc` | `Visit`: one walked entry, as a worker records it; `entry_path` |
| `source/walk/walker.lphc` | `walk_operand`: main-thread top level, `JobQueue`, `Harvest`, `Thread.spawnWith` workers, `walk_job` |
| `source/report/tree.lphc` | `Entry[lifetime ~tree]` with `unowned[~tree] var parent`; `build_tree` |
| `source/report/report.lphc` | `Report`: post-order sums, the lines to print, the grand total |
| `source/commands/du.lphc` | `run_du`: operands, ledger, output, exit status |

## Deterministic output with threads

Three things could make a parallel walk print differently from run to run,
and each is designed out:

1. **Order of lines.** Nothing is printed during the walk. Each worker
   records its job's entries in pre-order into its own list; the lists are
   stored by job number and grafted under their directory in name order
   after `join()`. The report is a post-order traversal of that tree.
2. **Which hard link counts.** GNU du counts a multiply-linked file (and,
   with several operands or `-L`, any file or directory) where the walk
   meets it first. Every such entry gets a *walk key*: eight hex digits per
   level (operand number, then the entry's index in its sorted directory),
   so that comparing keys as strings is comparing positions in a
   single-threaded pre-order walk. Workers *claim* `dev:ino` with their key in
   the `synchronized class Ledger`, which keeps the smallest key. After the
   join, an entry counts only if its key is the winner, which is the same
   whichever worker claimed first.
3. **Errors.** Workers store error messages in their visits; the report
   prints them to standard error in walk order, just before the entry's own
   line would have been reached.

The workers are `Thread.spawnWith` threads, not a `ThreadPool`: in Loup
1.26 `ThreadPool.run` runs each task inline on the calling thread.

## Shared state between threads

| Object | Kind | Why |
|---|---|---|
| `Options` | `@unsafe("sendable: ...")` class | filled by the parser before any thread starts; only read afterwards |
| `ExcludeList` | `Sendable` class with `let` fields and an `RwLock[int]` | workers match under the read lock; patterns are published under the write lock |
| `Ledger` | `synchronized class` | claims and totals updated by every worker |
| `JobQueue` | `synchronized class` | hands out the next job number |
| `Harvest` | `synchronized class` | the visit list of each job, stored by its worker |

## Directory handles

`DirHandle` is a `unique class` around the descriptor of `open(path,
O_RDONLY | O_DIRECTORY | O_CLOEXEC)`. Each entry is stat'ed with
`fstatat(fd, name, ..., AT_SYMLINK_NOFOLLOW)` relative to it, as GNU du does
through fts. The walker `del`s the handle before descending into
subdirectories, so a worker holds one descriptor at a time; on every other
path `finalize()` closes it at the end of the scope.

## Error handling

- Operand or entry that cannot be stat'ed: `cannot access 'P': REASON`
  (REASON from `errno`, read through `__errno_location`).
- Directory that cannot be opened: `cannot read directory 'P': REASON`; the
  directory is still printed with its own size.
- Usage errors: `Result[Options, ArgError]` from `parse_args`, printed by
  `cli.app` with the "Try 'du --help'" line (GNU leaves it out after a bad
  SIZE), status 1.
- Paths and walk keys are only built for entries that need them (a pattern
  to match, a directory to open, an error, a seen-inode claim): natively
  every string lives until the end of the run.

## Testing

- Unit tests (`tests/*_test.lphc`, native binaries): option parsing, SIZE
  parsing and formatting, glob matching and exclusion, walk keys and the
  ledger's claims, tree building and the report from hand-made visits, and
  the walker on a scratch tree it writes in its working directory.
- End-to-end (`tests/e2e.sh`): a scratch tree with known apparent sizes;
  expected disk usage is computed from `stat -c %b` so the tests pass on any
  file system; hard links, `-L` cycles, excludes, units, `-0`, errors, and
  the same output for `-j 1` and `-j 8`.

## Differences from GNU du

- Entries are walked and printed in byte order of their names; GNU du uses
  the order the file system returns them in.
- `-j N` / `--threads=N` is new.
- Not implemented: `--files0-from`, `--inodes`, `--time`, `--time-style`,
  `-x` mount-point details beyond comparing `st_dev`.
