#!/usr/bin/env bash
# Independent black-box contract: v4.6 stream operators and lifecycle.
# `<<` insertion and `>>` extraction over the supported stream surface, a
# complete open/close/reopen lifecycle, EOF (not an error), and a recoverable
# stream.* error taxonomy with structured code/category/source/line/message.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; cd "$t"

printf 'hello 42\nworld 7\n' > d.txt
printf 'a b c' > c.txt
printf 'true false' > bool.txt
printf 'one' > eof.txt

# Insertion: `<<` writes scalars, matching write()/write_line() semantics.
[ "$("$NIFT_BIN" -e 'o := ofstream("r.txt"); o << "hello"; o.close(); print(open("r.txt"))')" = 'hello' ]
[ "$("$NIFT_BIN" -e 'o := ofstream("r.txt"); o << "a" << " " << 42 << " " << true; o.close(); print(open("r.txt"))')" = 'a 42 true' ]
[ "$("$NIFT_BIN" -e 'o := ofstream("r.txt"); o.write("x"); o.write_line("y"); o.close(); print(open("r.txt"))')" = $'xy' ]

# Extraction: `>>` reads whitespace-delimited tokens into typed destinations.
[ "$("$NIFT_BIN" -e 's := ""; i := 0; f := ifstream("d.txt"); f >> s >> i; print(s); print(i); f.close()')" = $'hello\n42' ]
[ "$("$NIFT_BIN" -e 'a := ""; b := ""; d := ""; f := ifstream("c.txt"); f >> a >> b >> d; print(a + "," + b + "," + d); f.close()')" = 'a,b,c' ]
[ "$("$NIFT_BIN" -e 'x := false; y := true; f := ifstream("bool.txt"); f >> x >> y; print(x); print(y); f.close()')" = $'true\nfalse' ]

# EOF before a token leaves the destination unchanged and is not an error.
[ "$("$NIFT_BIN" -e 'a := ""; b := "sentinel"; f := ifstream("eof.txt"); f >> a; f >> b; print(a); print(b); f.close()')" = $'one\nsentinel' ]

# Reopen after close.
[ "$("$NIFT_BIN" -e 'o := ofstream(); o.open("a.txt"); o.write("a"); o.close(); o.open("b.txt"); o.write("b"); o.close(); print(open("a.txt") + open("b.txt"))')" = 'ab' ]

# Recoverable stream error taxonomy (code|category|source?|line?|message).
catch_code(){ # <expected-code> <operation>
  local out
  out=$("$NIFT_BIN" -e "try { $2 } catch(err) { print(err.code + \"|\" + err.category + \"|\" + (err.source != \"\") + \"|\" + (err.line > 0) + \"|\" + (err.message != \"\")) }")
  [ "$out" = "$1|stream|true|true|true" ] || { echo "expected $1 for $2, got: $out" >&2; exit 1; }
}
catch_code stream.open_failed  's := ifstream(); s.open("missing.txt")'
catch_code stream.open_failed  's := ofstream("nodir/x.txt")'
catch_code stream.read_failed  's := ifstream("/dev"); s.read(1)'

# Lifecycle misuse is fatal (not catchable).
fatal(){ if "$NIFT_BIN" -e "try { $1 } catch(e) { print(\"CAUGHT\") }" >"$t/o" 2>"$t/e"; then echo "accepted: $1" >&2; exit 1; fi; grep -q CAUGHT "$t/o" && { echo "caught: $1" >&2; exit 1; } || true; }
fatal 's := ofstream(); s.open("x.txt"); s.open("y.txt")'
fatal 's := ifstream(); s.close()'
fatal 's := ifstream("d.txt"); s.close(); s.read_line()'
fatal 's := ifstream("d.txt"); s.write("x")'

# Backend write/flush/close failures are recoverable on Linux.
if [ "$(uname -s)" = Linux ]; then
  catch_code stream.write_failed 'big := ""; for(i : range(1,5000)) { big += "0123456789abcdef" }; o := ofstream("/dev/full"); o.write(big)'
  catch_code stream.flush_failed 'o := ofstream("/dev/full"); o.write("x"); o.flush()'
  catch_code stream.close_failed 'o := ofstream("/dev/full"); o.write("x"); o.close()'
fi

printf 'PASS v4.6 streams\n'
