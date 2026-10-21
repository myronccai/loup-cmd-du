# loup-cmd-du

GNU `du` in [Loup](https://code-craft.ai/references/loup): estimate the
disk space used by files and directory trees. It walks each directory with
several worker threads and still prints the same lines in the same order on
every run, counts hard links once, and takes its sizes from `lstat(2)`
through the C library.

Part of the **loup-cmd** series of example applications: classic Linux and
Windows commands, and projects for each Loup execution mode, each in its own
repository under [myronccai](https://github.com/myronccai?tab=repositories&q=loup-cmd).
This one is a `host.native` (host-compiled) command.

## Requirements

- Linux x86-64 with glibc (the `struct stat` layout and the `open(2)` flags
  are Linux's; the directory listing goes through `/proc/self/fd`).
- [Loup Lite](https://github.com/code-craft-ai-company/loup-releases) 1.26.0
  or later; see [Installing Loup Lite](#installing-loup-lite).
- `make`, and `clang` 17 or later for the native build.

## Installing Loup Lite

This example is built and tested with **Loup Lite**, the free public build of
the Loup toolchain from [Code Craft AI](https://code-craft.ai), meant for
education and training. Code Craft AI publishes the official builds,
installers and signed checksums at
**<https://github.com/code-craft-ai-company/loup-releases>**, for Linux
(x86-64, arm64), macOS (Apple silicon, Intel) and Windows (x86-64).

Linux and macOS:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.sh | sh
```

Windows (PowerShell):

```powershell
irm https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.ps1 | iex
```

The installer picks the archive for your machine, checks it against the
release's `SHA256SUMS`, unpacks it into `~/.loup`
(`%LOCALAPPDATA%\Programs\Loup` on Windows) and puts its `bin` directory on
your `PATH`; it needs no administrator rights. You get `loup`, the Stage0
compiler `loup-bootstrap` and the Wasm runtime `loup-launcher`. Open a new
shell and check:

```sh
loup --version             # loup 1.26.0 or later
```

CI installs the exact version it tests with, 1.26.0. To do the same:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/download/v1.26.0/loup-install.sh | sh -s -- --version 1.26.0
```

To install by hand, download your platform's archive from the
[releases page](https://github.com/code-craft-ai-company/loup-releases/releases),
check it against `SHA256SUMS`, unpack it anywhere and add its `bin` directory to
`PATH`. The [loup-releases README](https://github.com/code-craft-ai-company/loup-releases#verify-a-download)
explains how to verify the Sigstore signature on `SHA256SUMS`.

Loup Lite leaves out Loup's cryptography library and the full set of Loup
packages; this example needs neither. Commercial use of Loup needs a
license: <https://code-craft.ai/loup/license>.

## Usage

```sh
make build                         # native binary: build/du
make ci                            # check, native unit tests, build, end-to-end tests
make run ARGS="-sh /usr/share"     # build, then run with ARGS
```

The binary is built by the self-hosted compiler (`loup build --target
native`). `make check` and the unit tests use Stage0 (`loup-bootstrap`),
whose test runner compiles each test into a native binary, so the code
sticks to what both native back ends compile the same way.

A small project tree; `-b` is `--apparent-size --block-size=1`, sizes in
bytes. `proj/build/app-latest` is a hard link to `proj/build/app`, and
`proj/run` a symbolic link to it:

```text
$ du -ab proj
500	proj/README
20000	proj/build/app
6000	proj/build/app.o
26000	proj/build
3000	proj/docs/guide.md
3000	proj/docs
9	proj/run
1200	proj/src/main.c
800	proj/src/util.c
2000	proj/src
31509	proj
$ du -ab -l proj | grep build
20000	proj/build/app
20000	proj/build/app-latest
6000	proj/build/app.o
46000	proj/build
$ du -b -d 1 --exclude='*.o' proj
20000	proj/build
3000	proj/docs
2000	proj/src
25509	proj
$ du -sbc proj/src proj/docs
2000	proj/src
3000	proj/docs
5000	total
$ du -sh proj
44K	proj
```

The hard link is counted and listed once, where the walk meets it first;
`-l` counts it twice. Disk usage (without `-b`) is allocated blocks, so it
depends on the file system. On a real tree:

```text
$ du -sh /usr/share/doc /usr/share/man /usr/share/locale
177M	/usr/share/doc
49M	/usr/share/man
71M	/usr/share/locale
$ du nope proj/README
du: cannot access 'nope': No such file or directory
4	proj/README
$ echo $?
1
```

## Options

| Option | Meaning |
|---|---|
| `-a`, `--all` | list files too, not only directories |
| `--apparent-size` | `st_size` instead of allocated blocks (directories count 0, as in GNU du) |
| `-B`, `--block-size=SIZE` | print sizes in units of SIZE (`1M`, `KB`, `4096`; a unit alone is printed after each size: `-BK` gives `12K`) |
| `-b`, `--bytes` | `--apparent-size --block-size=1` |
| `-c`, `--total` | end with a grand total |
| `-D`, `-H`, `--dereference-args` | follow symbolic links named on the command line |
| `-d`, `--max-depth=N` | list entries at most N levels below an operand |
| `-h`, `--human-readable` / `--si` | `4.0K`, `12M` (powers of 1024) / `4.1k` (powers of 1000) |
| `-j`, `--threads=N` | worker threads, 1 to 64 (default: one per CPU, at most 8) |
| `-k` / `-m` | units of 1024 / 1048576 bytes |
| `-L`, `--dereference` | follow all symbolic links (a link to an ancestor is skipped) |
| `-l`, `--count-links` | count a hard-linked file at every link |
| `-P`, `--no-dereference` | follow no symbolic links (the default) |
| `-S`, `--separate-dirs` | a directory's size leaves out its subdirectories |
| `-s`, `--summarize` | only the operands (`--max-depth=0`) |
| `-t`, `--threshold=SIZE` | leave out entries smaller than SIZE (larger than -SIZE if negative) |
| `--exclude=PATTERN`, `-X`, `--exclude-from=FILE` | skip what matches a shell pattern (`*` also matches `/`; tried on the whole path and on every part after a `/`) |
| `-x`, `--one-file-system` | skip everything on another file system |
| `-0`, `--null` | end lines with NUL instead of newline |
| `--help`, `--version` | |

Short options bundle (`-sh`, `-d1`, `-BM`), long options accept unambiguous
prefixes (`--max=1`), options may follow operands, and `--` ends them. With
no operand du walks `.`. Without a unit option the unit is the first of
`DU_BLOCK_SIZE`, `BLOCK_SIZE` and `BLOCKSIZE` that is set, else 1024 bytes
(512 with `POSIXLY_CORRECT`).

Exit status: `0` success, `1` if any file could not be read, or on a usage
error.

## Differences from the original

- Entries are walked and listed in byte order of their names (GNU du uses
  the order the file system returns them in). The order decides which hard
  link is counted, so the two can charge a link to different directories;
  totals agree.
- `-j N` / `--threads=N` is new.
- Not implemented: `--files0-from`, `--inodes`, `--time`, `--time-style`.
- A `--max-depth` below 0 is an error; SIZE values must fit in a signed
  64-bit integer (`-B 10E` is "too large").
- A directory cycle through a bind mount is skipped silently; GNU du warns
  about it.
- Error messages for `errno` values other than the common ones (ENOENT,
  EACCES, ENOTDIR, ELOOP, ...) are `Unknown error N`.

## What this example shows

- **OS threads with a deterministic result.** `walk/walker.lphc` gives each
  top-level subdirectory of an operand to a pool of `Thread.spawnWith`
  workers that take jobs from a `synchronized class JobQueue`. Nothing is
  printed during the walk: each worker records its job's entries in its own
  list, in the order a single-threaded walk would meet them, and hands it to
  a `synchronized class Harvest` under the job number; after `join()` the
  lists are spliced in name order. The output is the same for `-j 1` and
  `-j 16` (the end-to-end tests check it). The workers are plain
  `Thread`s: Loup 1.26's `ThreadPool.run` executes each task on the
  calling thread, so a pool would not walk anything in parallel.
- **A `synchronized class` with a rule that does not care who comes first.**
  `walk/ledger.lphc` keeps the seen-inode set and the walk's totals. Every
  entry that may be a repeat claims its `dev:ino` with a *walk key* (eight
  hex digits per level, so string order is pre-order); the ledger keeps the
  smallest key, which is the entry a sequential walk would have counted.
- **`RwLock`.** The exclude patterns (`walk/excludes.lphc`) are read by every
  worker under a read lock and published under the write lock; Loup 1.26's
  `RwLock` holds an `int`, so the lock's value is the number of published
  patterns.
- **`Sendable`, checked and asserted.** `ExcludeList`, `FileInfo`, `Visit`
  and the job records are `Sendable` because their fields are immutable. The
  parsed `Options` has plain `var` fields that only the parser writes, before
  any thread starts: that protocol is stated with
  `@unsafe("sendable: ...")`.
- **A `unique class` that owns a descriptor.** `DirHandle`
  (`fs/files.lphc`) wraps `open(path, O_DIRECTORY)`; entries are stat'ed with
  `fstatat` relative to it and listed through `/proc/self/fd/N`. Its
  `finalize()` closes the descriptor; the walker `del`s the handle before it
  descends, so a thread holds one descriptor at a time, and a unit test opens
  3,000 handles in a row to prove none leaks. It is lent out as
  `borrow dir: DirHandle`.
- **`unowned` parent links.** The report (`report/tree.lphc`) builds an
  `Entry[lifetime ~tree]` tree whose `unowned[~tree] var parent` does not
  keep the parent alive; each entry stores only its name and finds its path
  by following the parents.
- **Calling C with `@repr(C)` structs.** `struct stat` is declared field by
  field with C's `st_` names (144 bytes, checked with `size_of`), filled by
  `lstat`/`stat`/`fstatat` through `edits buf: StatBuf`, and copied into a
  `FileInfo` class at once. `errno` comes from `__errno_location()`, copied
  out with `memcpy` into a one-field C struct. The `extern native`
  declarations carry `@unsafe("threadSafe: ...")`.

## Layout

```text
source/main.lphc              # entry point
source/appinfo.lphc           # name, version, exit statuses, thread limits
source/cli/args.lphc          # Options (@unsafe sendable), getopt-style parse_args()
source/cli/usage.lphc         # --help and --version text
source/cli/app.lphc           # run(): parse, help/version, unit from the environment
source/size/units.lphc        # SIZE parsing, block sizes, -h/--si formatting
source/fs/files.lphc          # @repr(C) struct stat, libc calls, errno, unique class DirHandle
source/walk/excludes.lphc     # shell patterns, ExcludeList under an RwLock
source/walk/ledger.lphc       # synchronized class Ledger, walk keys
source/walk/visit.lphc        # Visit: one walked entry
source/walk/walker.lphc       # the parallel walk: JobQueue, Harvest, workers
source/report/tree.lphc       # Entry tree with unowned parent links
source/report/report.lphc     # post-order sums and lines, grand total
source/commands/du.lphc       # run_du(): operands, output, exit status
tests/*_test.lphc             # native unit tests (make test)
tests/helpers.lphc            # expect_text(), scratch files and links
tests/e2e.sh                  # end-to-end tests of build/du (make e2e)
specs/du/                     # requirements, design, tasks
```

[AGENTS.md](AGENTS.md) has every build and test command and the conventions
for changing the code.

## License

[MIT](LICENSE), copyright 2026 Code Craft AI LLC. The Loup skill in
[`skills/loup-programmer/`](skills/loup-programmer/) is copied from the Loup
project and is not covered by this license; it keeps the Loup project's terms.
