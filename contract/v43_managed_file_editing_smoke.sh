#!/usr/bin/env bash
set -euo pipefail
NIFT=${NIFT_BIN:?}; R=$(mktemp -d); trap 'rm -rf "$R"' EXIT; cd "$R"
printf 'ORIGINAL\n' > x.txt

# --- Lifecycle: closed access errors; open/close/reopen; double-open errors. ---
cat > l1.nift <<'NIFT'
f := file("x.txt")
f.open()
f.close()
f.open()
f.close()
print("ok")
NIFT
[[ "$("$NIFT" l1.nift)" == 'ok' ]]
for op in 'f.read()' 'f.write("x")' 'f.save()' 'f.revert()' 'f.close()'; do
  printf 'f := file("x.txt")\n%s\n' "$op" > lc.nift
  if "$NIFT" lc.nift >/dev/null 2>&1; then echo "closed op unexpectedly ok: $op" >&2; exit 1; fi
done
printf 'f := file("x.txt")\nf.open()\nf.open()\n' > dd.nift
if "$NIFT" dd.nift >/dev/null 2>&1; then echo "double-open ok" >&2; exit 1; fi

# --- Dirty close is rejected; save/revert then close works. ---
cat > d1.nift <<'NIFT'
f := file("x.txt")
f.open("rw")
f.replace_once("ORIGINAL", "EDITED")
f.close()
NIFT
if "$NIFT" d1.nift >/dev/null 2>&1; then echo "dirty close ok" >&2; exit 1; fi
cat > d2.nift <<'NIFT'
f := file("x.txt")
f.open("rw")
f.replace_once("ORIGINAL", "EDITED")
f.save()
f.close()
print(open("x.txt"))
NIFT
[[ "$("$NIFT" d2.nift)" == 'EDITED' ]]

# --- Working copy vs disk; revert discards unsaved edits. ---
printf 'SAVED' > y.txt
cat > w1.nift <<'NIFT'
f := file("y.txt")
f.open("rw")
f.replace_once("SAVED", "UNSAVED")
print(f.read_all())
print(open("y.txt"))
f.revert()
print(f.modified())
print(f.read_all())
f.close()
NIFT
[[ "$("$NIFT" w1.nift)" == $'UNSAVED\nSAVED\nfalse\nSAVED' ]]

# --- modified(): open clean, after edit, after save, after revert. ---
cat > m1.nift <<'NIFT'
f := file("y.txt")
f.open("rw")
print(f.modified())
f.replace_once("SAVED", "NEXT")
print(f.modified())
f.save()
print(f.modified())
f.replace_once("NEXT", "LAST")
f.revert()
print(f.modified())
f.close()
NIFT
[[ "$("$NIFT" m1.nift)" == $'false\ntrue\nfalse\nfalse' ]]

# --- Modes: w does not truncate disk before save; a appends at save; r is RO. ---
printf 'DATA' > z.txt
cat > w2.nift <<'NIFT'
f := file("z.txt")
f.open("w")
print(open("z.txt"))
f.write("REPLACED")
print(open("z.txt"))
f.save()
print(open("z.txt"))
f.close()
NIFT
[[ "$("$NIFT" w2.nift)" == $'DATA\nDATA\nREPLACED' ]]
cat > a2.nift <<'NIFT'
f := file("z.txt")
f.open("a")
print(open("z.txt"))
f.write("+TAIL")
print(open("z.txt"))
f.save()
print(open("z.txt"))
f.close()
NIFT
[[ "$("$NIFT" a2.nift)" == $'REPLACED\nREPLACED\nREPLACED+TAIL' ]]
printf 'f := file("z.txt")\nf.open("r")\nf.write("x")\n' > ro.nift
if "$NIFT" ro.nift >/dev/null 2>&1; then echo "read-only write ok" >&2; exit 1; fi

# --- Read surface parity with ifstream. ---
printf 'l1\nl2' > r.txt
cat > rd.nift <<'NIFT'
f := file("r.txt")
f.open("r")
print(f.read_line())
print(f.read_line())
print(f.read_line() == null)
print(f.eof())
f.close()
s := ifstream("r.txt")
print(s.read_line())
print(s.read_line())
print(s.read_line() == null)
print(s.eof())
close(s)
NIFT
[[ "$("$NIFT" rd.nift)" == $'l1\nl2\ntrue\ntrue\nl1\nl2\ntrue\ntrue' ]]

# --- Seek/tell byte positions. ---
cat > sk.nift <<'NIFT'
f := file("r.txt")
f.open("r")
f.seek(1)
print(f.tell())
print(f.read_all())
f.seek(0)
print(f.read_all())
f.close()
NIFT
[[ "$("$NIFT" sk.nift)" == $'1\n1\nl2\nl1\nl2' ]]
printf 'f := file("r.txt")\nf.open("r")\nf.seek(99)\n' > skb.nift
if "$NIFT" skb.nift >/dev/null 2>&1; then echo "seek past end ok" >&2; exit 1; fi
printf 'f := file("r.txt")\nf.open("r")\nf.seek(-1)\n' > skc.nift
if "$NIFT" skc.nift >/dev/null 2>&1; then echo "negative seek ok" >&2; exit 1; fi

# --- replace() count and non-overlap; replace_once ambiguity no-mutation. ---
printf 'abab' > ab.txt
cat > rp.nift <<'NIFT'
f := file("ab.txt")
f.open("rw")
print(f.replace("ab", "X"))
print(f.read_all())
f.revert()
f.close()
NIFT
[[ "$("$NIFT" rp.nift)" == $'2\nXX' ]]
cat > rp2.nift <<'NIFT'
f := file("ab.txt")
f.open("rw")
f.replace_once("ab", "X")
NIFT
if "$NIFT" rp2.nift >/dev/null 2>&1; then echo "ambiguous replace_once ok" >&2; exit 1; fi
printf 'abab' > ab2.txt
cat > rp3.nift <<'NIFT'
f := file("ab2.txt")
f.open("rw")
f.replace_once("ab", "X")
print(open("ab2.txt"))
NIFT
if "$NIFT" rp3.nift >/dev/null 2>&1; then echo "ambiguous mutated disk" >&2; exit 1; fi

# --- Insertion: byte positions; anchor ambiguity; prepend/append. ---
printf 'hello' > h.txt
cat > in.nift <<'NIFT'
f := file("h.txt")
f.open("rw")
f.insert(0, "<")
f.insert_after("hello", ">")
f.prepend("START ")
f.append(" END")
f.save()
f.close()
print(open("h.txt"))
NIFT
[[ "$("$NIFT" in.nift)" == 'START <hello> END' ]]
printf 'xx' > xx.txt
cat > ia.nift <<'NIFT'
f := file("xx.txt")
f.open("rw")
f.insert_after("x", "!")
print(f.read_all())
f.revert()
f.close()
NIFT
if "$NIFT" ia.nift >/dev/null 2>&1; then echo "ambiguous insert_after ok" >&2; exit 1; fi
printf 'xx' > xx2.txt
cat > ia2.nift <<'NIFT'
f := file("xx2.txt")
f.open("rw")
f.insert_after("x", "!")
print(open("xx2.txt"))
NIFT
if "$NIFT" ia2.nift >/dev/null 2>&1; then echo "ambiguous insert mutated disk" >&2; exit 1; fi

# --- Aliases share the managed session; distinct constructions do not. ---
printf 'V' > v.txt
cat > al.nift <<'NIFT'
a := file("v.txt")
b := a
print(same(a, b))
a.open("rw")
b.replace_once("V", "W")
print(a.read_all())
b.save()
b.close()
print(open("v.txt"))
c := file("v.txt")
print(same(a, c))
NIFT
[[ "$("$NIFT" al.nift)" == $'true\nW\nW\nfalse' ]]

# --- copy/move/remove closed; rejected while open. ---
printf 'C' > c.txt
cat > cp.nift <<'NIFT'
f := file("c.txt")
d := f.copy("d.txt")
print(d.exists())
f.move("m.txt")
print(exists("c.txt"))
print(f.path())
print(exists("m.txt"))
f2 := file("m.txt")
f2.remove()
print(exists("m.txt"))
NIFT
[[ "$("$NIFT" cp.nift)" == $'true\nfalse\n'$R$'/m.txt\ntrue\nfalse' ]]
printf 'f := file("m.txt")\nf.open()\nf.copy("n.txt")\n' > co.nift
if "$NIFT" co.nift >/dev/null 2>&1; then echo "copy while open ok" >&2; exit 1; fi

# --- Host exit with an open FileValue errors and does not save dirty state. ---
printf 'KEEP' > keep.txt
cat > he.nift <<'NIFT'
f := file("keep.txt")
f.open("rw")
f.replace_once("KEEP", "GONE")
NIFT
if "$NIFT" he.nift >/dev/null 2>&1; then echo "open dirty exit ok" >&2; exit 1; fi
[[ "$(cat keep.txt)" == 'KEEP' ]]

# --- Error recovery: an ambiguous edit errors but the REPL session and the
# FileValue remain usable (recoverable errors do not poison the session). ---
printf 'abab' > ab.txt
repl="$(cd "$R" && printf 'f := file("ab.txt")\nf.open("rw")\nf.replace_once("ab", "X")\nf.replace_once("abab", "OK")\nf.save()\nf.close()\nprint(open("ab.txt"))\nquit\n' | "$NIFT" 2>&1 || true)"
grep -q 'replace_once: expected exactly one match' <<<"$repl"
grep -q 'OK' <<<"$repl"