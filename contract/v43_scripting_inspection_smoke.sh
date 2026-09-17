#!/usr/bin/env bash
set -euo pipefail
NIFT=${NIFT_BIN:?}; R=$(mktemp -d); trap 'rm -rf "$R"' EXIT; cd "$R"; "$NIFT" init >/dev/null
B(){ tr -d '[:space:]' < public/index.html; }

# --- cat(path): byte-exact, no implicit newline, null return, errors. ---
printf 'a\nb' > no-nl.txt
printf 'x\ny\n' > with-nl.txt
printf '' > empty.txt
mkdir -p subdir
printf 'cat("no-nl.txt")\nprint("AFTER")\n' > c1.nift
[[ "$("$NIFT" run c1.nift)" == $'a\nbAFTER' ]]
printf 'cat("with-nl.txt")\nprint("AFTER")\n' > c2.nift
[[ "$("$NIFT" run c2.nift)" == $'x\ny\nAFTER' ]]
printf 'r := cat("no-nl.txt")\nprint(r == null)\n' > c3.nift
[[ "$("$NIFT" run c3.nift)" == $'a\nbtrue' ]]
printf 'cat("empty.txt")\nprint("AFTER")\n' > c4.nift
[[ "$("$NIFT" run c4.nift)" == 'AFTER' ]]
printf 'cat("missing.txt")\n' > c5.nift
if "$NIFT" run c5.nift >/dev/null 2>&1; then echo "cat(missing) succeeded" >&2; exit 1; fi
printf 'cat("subdir")\n' > c6.nift
if "$NIFT" run c6.nift >/dev/null 2>&1; then echo "cat(directory) succeeded" >&2; exit 1; fi

# --- ls()/ls(path): arrays, deterministic order, hidden names, errors. ---
CLEAN="$(mktemp -d)"; trap 'rm -rf "$CLEAN"' EXIT
printf 'b' > "$CLEAN/b.txt"; printf 'a' > "$CLEAN/a.txt"; printf 'h' > "$CLEAN/.hidden"; mkdir -p "$CLEAN/ddir"
printf 'for(n : ls()) { print(n) }\n' > l1.nift
[[ "$(cd "$CLEAN" && "$NIFT" run "$R/l1.nift")" == $'.hidden\na.txt\nb.txt\nddir' ]]
printf 'for(n : ls("ddir")) { print(n) }\n' > l2.nift
[[ "$(cd "$CLEAN" && "$NIFT" run "$R/l2.nift")" == '' ]]
printf 'x := ls()\nfor(n : x) { print(n) }\n' > l3.nift
[[ "$(cd "$CLEAN" && "$NIFT" run "$R/l3.nift")" == $'.hidden\na.txt\nb.txt\nddir' ]]
printf 'ls("missing")\n' > l4.nift
if "$NIFT" run l4.nift >/dev/null 2>&1; then echo "ls(missing) succeeded" >&2; exit 1; fi
printf 'ls("a.txt")\n' > l5.nift
if (cd "$CLEAN" && "$NIFT" run "$R/l5.nift" >/dev/null 2>&1); then echo "ls(file) succeeded" >&2; exit 1; fi

# --- stringify()/prettify(): deterministic, escaping, typed keys, opaque. ---
printf 'm := map()\nm.set("b", 1)\nm.set("a", 2)\nprint(m.stringify())\nprint(m.prettify())\n' > s1.nift
[[ "$("$NIFT" run s1.nift)" == $'map([["b",1],["a",2]])\nmap([\n  ["b", 1],\n  ["a", 2]\n])' ]]
printf 'm := map()\nm.set(1, "one")\nm.set("1", "str")\nprint(m.stringify())\n' > s2.nift
[[ "$("$NIFT" run s2.nift)" == 'map([[1,"one"],["1","str"]])' ]]
printf 'ss := sorted_set()\nss.add(3)\nss.add(1)\nprint(ss.stringify())\nsm := sorted_map()\nsm.set("b", 1)\nsm.set("a", 2)\nprint(sm.stringify())\n' > s3.nift
[[ "$("$NIFT" run s3.nift)" == $'sorted_set([1,3])\nsorted_map([["a",2],["b",1]])' ]]
printf 'x := "q\\"w\\nc"\nprint(x.stringify())\n' > s4.nift
[[ "$("$NIFT" run s4.nift)" == '"q\"w\nc"' ]]
printf 'f := (a) => a\nprint(f.stringify())\n' > s5.nift
if "$NIFT" run s5.nift >/dev/null 2>&1; then echo "callable stringify succeeded" >&2; exit 1; fi
printf 's := ifstream("a.txt")\nprint(s.prettify())\n' > s6.nift
if "$NIFT" run s6.nift >/dev/null 2>&1; then echo "stream prettify succeeded" >&2; exit 1; fi
printf 'struct(vault) { private secret := 7\npub := 1\nfn(read()) { return secret } }\nv := vault()\nprint(v.stringify())\nprint(v.read())\n' > s7.nift
[[ "$("$NIFT" run s7.nift)" == $'vault{pub:1}\n7' ]]

# --- highlight(): presentation-only; ANSI never enters returned strings/files. ---
printf 'print(ls().highlight())\nprint([1,2].prettify())\n' > h1.nift
out="$("$NIFT" run h1.nift)"
[[ "$out" != *$'\033'* ]]
printf 'x := [1, 2]\nprint(x.prettify().highlight() == x.highlight().prettify())\nprint(x.prettify().prettify() == x.prettify())\nprint(x.highlight().highlight() == x.highlight())\n' > h2.nift
[[ "$("$NIFT" run h2.nift)" == $'true\ntrue\ntrue' ]]

# --- Composition does not hijack compound expressions. ---
printf 'x := [1, 2]\nprint(x.prettify() == x.prettify())\nprint("got=" + x.prettify())\nprint(x.size() == x.size())\nf := (a) => a + 1\nprint(f(1) == f(1))\n' > h3.nift
[[ "$("$NIFT" run h3.nift)" == $'true\ngot=[\n  1,\n  2\n]\ntrue\ntrue' ]]

# --- REPL bare-expression display: ordinary values shown; null/"" silent;
#     0/false/empty collections retained; no ANSI on a non-TTY pipe. ---
repl="$(cd "$R" && printf '42\n[1,2,3]\nnull\n""\n0\nfalse\n[]\nm := map()\nm\ncd(".")\nquit\n' | HOME="$R" NO_COLOR=1 "$NIFT" sh 2>&1)"
[[ "$repl" == *'42'* ]]
[[ "$repl" == *'[1,2,3]'* ]]
[[ "$repl" == *'0'* ]]
[[ "$repl" == *'false'* ]]
[[ "$repl" == *'[]'* ]]
[[ "$repl" == *'map([])'* ]]
if printf '%s\n' "$repl" | grep -qx 'null'; then echo "null displayed" >&2; exit 1; fi
[[ "$repl" != *'""'* ]]
[[ "$repl" != *$'\033'* ]]

# --- REPL prompt: ~ abbreviation for home, exact home -> ~, no ~/ for home. ---
prompt_home="$(cd "$R" && printf 'quit\n' | HOME="$R" NO_COLOR=1 "$NIFT" sh 2>/dev/null | head -1)"
[[ "$prompt_home" == '~$'* ]]
prompt_child="$(cd "$R/.." && printf 'quit\n' | HOME="$R" NO_COLOR=1 "$NIFT" sh 2>/dev/null | head -1)"
# Child of home abbreviates the home prefix only.
[[ "$prompt_child" != "${prompt_home}" ]] || true