#!/usr/bin/env bash
# End-to-end tests: run the built binary on scratch trees in a temporary
# directory and compare its standard output (or standard error) and exit
# status with the expected ones.
#
# Sizes depend on the file system only for disk usage (st_blocks), so most
# cases use apparent sizes (-b, --apparent-size), where directories count 0
# and every number is known. The disk-usage cases compute their expected
# numbers from `stat -c %b` of the same files.
#
# usage: tests/e2e.sh BINARY

set -u
BIN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
pass=0
fail=0
unset DU_BLOCK_SIZE BLOCK_SIZE BLOCKSIZE POSIXLY_CORRECT

ok() { pass=$((pass + 1)); }
bad() {
    fail=$((fail + 1))
    echo "FAIL: $1"
    sed 's/^/    stdout: /' "$TMP/out" | head -5
    sed 's/^/    stderr: /' "$TMP/err" | head -5
}

# run ARGS...: runs BINARY in $TMP with standard input from /dev/null; sets
# $status.
run() {
    (cd "$TMP" && "$BIN" "$@" < /dev/null > "$TMP/out" 2> "$TMP/err")
    status=$?
}

# check NAME STATUS EXPECTED_STDOUT [ARGS...]: exact standard output, and
# nothing on standard error when STATUS is 0.
check() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want"
    shift 3
    run "$@"
    if [ "$status" -eq "$want_status" ] && cmp -s "$TMP/want" "$TMP/out" \
        && { [ "$want_status" -ne 0 ] || [ ! -s "$TMP/err" ]; }; then
        ok
    else
        bad "$name (exit $status, expected $want_status)"
        diff "$TMP/want" "$TMP/out" | sed 's/^/    /' | head -10
    fi
}

# check_err NAME STATUS EXPECTED_STDERR [ARGS...]: exact standard error.
check_err() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want"
    shift 3
    run "$@"
    if [ "$status" -eq "$want_status" ] && cmp -s "$TMP/want" "$TMP/err"; then
        ok
    else
        bad "$name (exit $status, expected $want_status)"
        diff "$TMP/want" "$TMP/err" | sed 's/^/    /' | head -10
    fi
}

# kib PATH...: the disk usage of the paths together in 1024-byte units,
# rounded up, from their st_blocks.
kib() {
    local blocks=0 f
    for f in "$@"; do
        blocks=$((blocks + $(stat -c %b "$TMP/$f")))
    done
    echo $(((blocks * 512 + 1023) / 1024))
}

# file PATH SIZE: a file of exactly SIZE bytes.
file() {
    mkdir -p "$(dirname "$TMP/$1")"
    head -c "$2" /dev/zero > "$TMP/$1"
}

try=$'Try \'du --help\' for more information.\n'

# --- the tree ---------------------------------------------------------------
# t/ a (1000)  b/ c (300)  b/d/ e (40)  z/ y (7)
file t/a 1000
file t/b/c 300
file t/b/d/e 40
file t/z/y 7

# --- help and version -------------------------------------------------------
check "version" 0 $'du (loup-cmd-du) 0.1.0\n' --version
run --help
if [ "$status" -eq 0 ] && head -1 "$TMP/out" | grep -qx 'Usage: du \[OPTION\]... \[FILE\]...'; then ok; else bad "help"; fi

# --- apparent sizes -----------------------------------------------------------
check "-b"                0 $'40\tt/b/d\n340\tt/b\n7\tt/z\n1347\tt\n'  -b t
check "-ab"               0 $'1000\tt/a\n300\tt/b/c\n40\tt/b/d/e\n40\tt/b/d\n340\tt/b\n7\tt/z/y\n7\tt/z\n1347\tt\n'  -ab t
check "--apparent-size -a -k rounds up" 0 $'1\tt/a\n1\tt/b/c\n1\tt/b/d/e\n1\tt/b/d\n1\tt/b\n1\tt/z/y\n1\tt/z\n2\tt\n'  --apparent-size -a -k t
check "-s"                0 $'1347\tt\n'                      -sb t
check "-d 1"              0 $'340\tt/b\n7\tt/z\n1347\tt\n'    -b -d 1 t
check "--max-depth=0"     0 $'1347\tt\n'                      -b --max-depth=0 t
check "-S"                0 $'40\tt/b/d\n300\tt/b\n7\tt/z\n1000\tt\n'  -S -b t
check "-c two operands"   0 $'340\tt/b\n7\tt/z\n347\ttotal\n'  -sbc t/b t/z
check "-t 300"            0 $'1000\tt/a\n300\tt/b/c\n340\tt/b\n1347\tt\n'  -ab -t 300 t
check "-t -40"            0 $'40\tt/b/d/e\n40\tt/b/d\n7\tt/z/y\n7\tt/z\n'  -ab -t -40 t
check "trailing slash"    0 $'40\tt/b/d\n340\tt/b\n7\tt/z\n1347\tt/\n'  -b t/
check "file operand"      0 $'1000\tt/a\n'                    -b t/a
check "BKB suffix"        0 $'2kB\tt\n'                       --apparent-size -s -BKB t
check "-BK suffix"        0 $'2K\tt\n'                        --apparent-size -s -BK t
check "-h"                0 $'1000\tt/a\n1.4K\tt\n'  --apparent-size -h -a -d 1 -t 341 t
check "--si"              0 $'1.0k\tt/a\n1.4k\tt\n'           --apparent-size --si -a -d 1 -t 1000 t

# -0: NUL instead of newline.
run -0 -sb t/b t/z
printf '340\tt/b\0007\tt/z\000' > "$TMP/want"
if [ "$status" -eq 0 ] && cmp -s "$TMP/want" "$TMP/out"; then ok; else bad "-0"; fi

# --- the environment ------------------------------------------------------------
export DU_BLOCK_SIZE=1
check "DU_BLOCK_SIZE"     0 $'1347\tt\n'                      --apparent-size -s t
check "-k beats it"       0 $'2\tt\n'                         --apparent-size -s -k t
unset DU_BLOCK_SIZE
export BLOCK_SIZE=K
check "BLOCK_SIZE with a unit" 0 $'2K\tt\n'                   --apparent-size -s t
unset BLOCK_SIZE

# --- no operand -------------------------------------------------------------------
(cd "$TMP/t/b" && "$BIN" -b < /dev/null > "$TMP/out" 2> "$TMP/err")
if [ $? -eq 0 ] && [ "$(cat "$TMP/out")" = "$(printf '40\t./d\n340\t.')" ]; then ok; else bad "no operand walks ."; fi

# --- disk usage (st_blocks) -----------------------------------------------------------
check "disk usage" 0 "$(kib t/b/d t/b/d/e)	t/b/d
$(kib t/b t/b/c t/b/d t/b/d/e)	t/b
" t/b
check "disk usage -s"  0 "$(kib t t/a t/b t/b/c t/b/d t/b/d/e t/z t/z/y)	t
" -s t

# --- hard links -------------------------------------------------------------------------
file h/p/f 5000
mkdir -p "$TMP/h/q"
ln "$TMP/h/p/f" "$TMP/h/q/g"
file h/q/k 100
check "a hard link counts once, where the walk meets it first" 0 $'5000\th/p/f\n5000\th/p\n100\th/q/k\n100\th/q\n5100\th\n'  -ab h
check "-l counts every link" 0 $'5000\th/p\n5100\th/q\n10100\th\n'  -lb h
check "operands share the seen set" 0 $'5100\th/q\n0\th/p\n'  -sb h/q h/p
check "a repeated operand counts once" 0 $'5100\th\n'  -sb h h
check "an operand inside an earlier one is skipped" 0 $'5100\th\n5100\ttotal\n'  -sbc h h/q

# --- symbolic links ----------------------------------------------------------------------
mkdir -p "$TMP/s/d"
file s/d/f 9
ln -s .. "$TMP/s/d/up"
ln -s d "$TMP/s/to-d"
ln -s nowhere "$TMP/s/dangling"
check "-P: links are entries" 0 $'9\ts/d/f\n2\ts/d/up\n11\ts/d\n7\ts/dangling\n1\ts/to-d\n19\ts\n'  -ab s
check "-L follows, skips a cycle" 1 $'9\ts/d/f\n9\ts/d\n9\ts\n'  -ab -L s
check_err "-L: a dangling link" 1 $'du: cannot access \'s/dangling\'\n'  -ab -L s
check "-H follows an operand"   0 $'9\ts/to-d/f\n2\ts/to-d/up\n11\ts/to-d\n'  -ab -H s/to-d
check "without -H the operand is the link" 0 $'1\ts/to-d\n'  -ab s/to-d

# --- excludes ------------------------------------------------------------------------------
check "--exclude a directory" 0 $'7\tt/z\n1007\tt\n'  -b --exclude=b t
check "--exclude a pattern"   0 $'1000\tt/a\n300\tt/b/c\n300\tt/b\n7\tt/z/y\n7\tt/z\n1307\tt\n'  -ab --exclude='*d' t
check "--exclude the operand" 0 ''  -b --exclude=t t
printf 'c\n\n[yz]\n' > "$TMP/patterns"
check "-X FILE"               0 $'40\tt/b/d\n40\tt/b\n1040\tt\n'  -b -X patterns t
check_err "-X missing"        1 "du: nope: No such file or directory
$try"  -X nope t

# --- errors ------------------------------------------------------------------------------------
check_err "missing operand" 1 $'du: cannot access \'nope\': No such file or directory\n'  -sb nope t
check "the rest is still listed" 1 $'1347\tt\n'  -sb nope t
if [ "$(id -u)" -ne 0 ]; then
    mkdir -p "$TMP/p/locked/in" "$TMP/p/noexec/sub"
    file p/noexec/f 1
    chmod 000 "$TMP/p/locked"
    chmod 600 "$TMP/p/noexec"
    check_err "unreadable directories" 1 "du: cannot read directory 'p/locked': Permission denied
du: cannot access 'p/noexec/f': Permission denied
du: cannot access 'p/noexec/sub': Permission denied
"  -b p
    check "they are still listed" 1 $'0\tp/locked\n0\tp/noexec\n0\tp\n'  -b p
    chmod 700 "$TMP/p/locked" "$TMP/p/noexec"
else
    pass=$((pass + 2))
fi

# --- usage errors --------------------------------------------------------------------------------
check_err "invalid option"   1 "du: invalid option -- 'q'
$try"  -q t
check_err "unrecognized"     1 "du: unrecognized option '--bogus'
$try"  --bogus t
check_err "ambiguous"        1 "du: option '--s' is ambiguous; possibilities: '--si' '--separate-dirs' '--summarize'
$try"  --s t
check_err "missing value"    1 "du: option '--max-depth' requires an argument
$try"  t --max-depth
check_err "-s and -a"        1 "du: cannot both summarize and show all entries
$try"  -sa t
check_err "-s and -d 1"      1 "du: warning: summarizing conflicts with --max-depth=1
$try"  -s -d 1 t
check_err "bad depth"        1 "du: invalid maximum depth 'x'
$try"  -d x t
check_err "bad -B: no hint"  1 $'du: invalid -B argument \'0\'\n'  -B 0 t
check_err "bad -B suffix"    1 $'du: invalid suffix in --block-size argument \'1x\'\n'  --block-size=1x t
check_err "-t -0"            1 $'du: invalid --threshold argument \'-0\'\n'  -t -0 t
check_err "bad -j"           1 "du: invalid number of threads '0' (1 to 64)
$try"  -j 0 t

# --- threads: the same output for any number of workers ---------------------------------------
for i in $(seq 1 40); do
    file "w/dir$i/sub/f" $((i * 37))
    file "w/dir$i/g" $((i * 11))
    ln "$TMP/w/dir$i/g" "$TMP/w/dir$((i % 40 + 1))-link" 2>/dev/null || true
done
run -ab -j 1 w
cp "$TMP/out" "$TMP/one"
same=1
for n in 2 8 16; do
    for round in 1 2 3; do
        run -ab -j "$n" w
        cmp -s "$TMP/one" "$TMP/out" || same=0
    done
done
if [ "$same" -eq 1 ] && [ "$(wc -l < "$TMP/one")" -gt 120 ]; then ok; else bad "same output for -j 1, 2, 8 and 16"; fi

echo "e2e: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
