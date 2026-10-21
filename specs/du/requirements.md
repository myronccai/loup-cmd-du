# Requirements: du

## Introduction

`du` estimates the disk space used by files and directory trees, like GNU
`du` from coreutils. It walks each directory with several worker threads
and still prints the same lines, in the same order, on every run: the
order of a single-threaded walk in sorted name order. It is the
host-compiled (`host.native`) concurrency example of the loup-cmd series:
OS threads, a reader-writer lock, a `synchronized class`, `Sendable`
classes, `unowned` parent links and a `unique class` that owns an open
directory descriptor.

## Requirements

### Requirement 1: Sizes

**User Story:** As a user, I want to know how much space a tree takes so
that I can find what fills a disk.

#### Acceptance Criteria

1. THE program SHALL take each file's size from `lstat`: `st_blocks` x 512
   bytes by default, `st_size` with `--apparent-size`.
2. THE size of a directory SHALL be its own size plus the sizes of
   everything below it that is counted.
3. WHEN a file with more than one hard link is met again, THE program SHALL
   count and print it only at its first place in walk order; with `-l` it
   SHALL count every link.
4. WHEN there is more than one operand, or `-L` is given, THE program SHALL
   count every file and directory only once over the whole run, and SHALL
   skip a directory it has already counted (as GNU du does).
5. THE walk order SHALL be pre-order with the entries of each directory in
   byte order of their names; "first" in 1.3 and 1.4 means first in this
   order, whatever the thread scheduling.

### Requirement 2: Output

**User Story:** As a user, I want GNU du's output so that my scripts keep
working.

#### Acceptance Criteria

1. THE program SHALL print `SIZE<TAB>PATH` lines, a directory after
   everything below it (post-order), the operands in command-line order.
2. WHEN `-a` is given, THE program SHALL print files too; WHEN `-s` is
   given, only the operands; WHEN `-d N` / `--max-depth=N` is given, only
   entries at most N levels below an operand. An operand is always printed.
3. THE path SHALL be the operand as given for the operand itself, and the
   operand without trailing slashes, `/`, and the names below it otherwise.
4. WHEN `-c` is given, THE program SHALL end with `SIZE<TAB>total`, the sum of
   everything counted.
5. WHEN `-0` is given, THE program SHALL end each line with a NUL byte
   instead of a newline.
6. WHEN `-S` is given, a directory's size SHALL NOT include its
   subdirectories.
7. WHEN `-t SIZE` is given, THE program SHALL omit entries smaller than SIZE
   (larger than -SIZE when SIZE is negative); the total is not affected.

### Requirement 3: Units

**User Story:** As a user, I want sizes in the unit I can read.

#### Acceptance Criteria

1. THE default unit SHALL be 1024 bytes, or the value of `DU_BLOCK_SIZE`,
   `BLOCK_SIZE` or `BLOCKSIZE` (first one set), and sizes SHALL be rounded
   up to whole units.
2. `-k`, `-m`, `-b` (apparent size in bytes) and `-B SIZE` SHALL set the
   unit. SIZE is an integer and/or a unit (`K`, `M`, `G`, `T`, `P`, `E`,
   `Z`, `Y`, powers of 1024; `KB`, `MB`, ... powers of 1000; `KiB`, ...);
   WHEN SIZE has no number, the unit SHALL be printed after each size.
3. `-h` SHALL print sizes like `4.0K`, `12M` (powers of 1024, rounded up,
   one decimal below 10) and `--si` the same with powers of 1000 (`4.1k`).
4. WHEN a SIZE is not valid, THE program SHALL say `invalid -B argument`,
   `invalid suffix in -B argument` or `-B argument ... too large`.

### Requirement 4: What is walked

**User Story:** As a user, I want to leave parts of the tree out.

#### Acceptance Criteria

1. `--exclude=PATTERN` and `-X FILE` (one pattern per line) SHALL skip every
   file and directory whose path, or a part of it after a `/`, matches the
   shell pattern (`*`, `?`, `[...]`, `\`); `*` also matches `/`.
2. `-x` SHALL skip everything on another file system than its operand.
3. Symbolic links SHALL not be followed (`-P`, the default); `-L` SHALL
   follow all of them, `-H`/`-D` only those named on the command line.
   Under `-L` a link to one of its own ancestors SHALL be skipped.
4. WHEN no operand is given, THE program SHALL walk `.`.

### Requirement 5: Parallel walk

**User Story:** As a user with a big tree on a fast disk, I want the walk to
use several CPUs.

#### Acceptance Criteria

1. THE program SHALL walk the subdirectories of each operand on up to N
   worker threads (`-j N` / `--threads=N`; default: the number of CPUs, at
   most 8).
2. THE output, the error messages and the exit status SHALL NOT depend on N
   or on the scheduling of the threads.

### Requirement 6: Errors and exit status

**User Story:** As a script author, I want GNU du's messages and statuses.

#### Acceptance Criteria

1. WHEN an operand or entry cannot be read, THE program SHALL print
   `du: cannot access 'PATH': REASON` or `du: cannot read directory 'PATH':
   REASON` on standard error, go on, and exit with status 1.
2. A usage error SHALL print `du: MESSAGE` and `Try 'du --help' for more
   information.` and exit with status 1; `-s` with `-a` is a usage error, and
   so is `-s` with a `--max-depth` other than 0.
3. Short options SHALL bundle (`-sh`, `-d1`, `-BM`) and long options SHALL
   accept unambiguous prefixes (`--max=1`) and `=VALUE` or a separate value;
   `--` ends the options.
4. `--help` SHALL print the help and `--version` the line
   `du (loup-cmd-du) 0.1.0`, both with status 0.
