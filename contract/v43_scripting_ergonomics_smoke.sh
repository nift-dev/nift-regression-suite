#!/usr/bin/env bash
set -euo pipefail
NIFT=${NIFT_BIN:?}; R=$(mktemp -d); trap 'rm -rf "$R"' EXIT; cd "$R"

# --- String parsing/search. ---
cat > s1.nift <<'NIFT'
print(" a,b,,c, ".trim().split(",").stringify())
print("hello".length())
print("hello".index_of("ll"))
print("hello".last_index_of("l"))
print("abc".contains("b"))
print("abc".starts_with("a"))
print("abc".ends_with("c"))
print("hello".index_of("z"))
print("".index_of("z"))
NIFT
[[ "$("$NIFT" run s1.nift)" == $'["a","b","","c",""]\n5\n2\n3\ntrue\ntrue\ntrue\n-1\n-1' ]]

# --- split("") is UTF-8 code points; empty and no-delimiter cases. ---
cat > s2.nift <<'NIFT'
print("abc".split("").stringify())
print("".split("").stringify())
print("abab".split("ab").stringify())
print("a,,b".split(",").stringify())
print("é🙂".split("").stringify())
print("é🙂".length())
NIFT
[[ "$("$NIFT" run s2.nift)" == $'["a","b","c"]\n[]\n["","",""]\n["a","","b"]\n["é","🙂"]\n2' ]]
# split() arity error.
printf 'print("x".split())\n' > s2b.nift
if "$NIFT" run s2b.nift >/dev/null 2>&1; then echo "split() arity succeeded" >&2; exit 1; fi

# --- trim family, case, replace. ---
cat > s3.nift <<'NIFT'
print("  x  ".trim() == "x")
print("  x  ".trim_start() == "x  ")
print("  x  ".trim_end() == "  x")
print("a\tb\n".trim() == "a\tb")
print("abc".to_upper())
print("ABC".to_lower())
print("foo foo".replace("foo", "bar"))
print("aaaa".replace("aa", "b"))
print("abc".replace("z", "y"))
NIFT
[[ "$("$NIFT" run s3.nift)" == $'true\ntrue\ntrue\ntrue\nABC\nabc\nbar bar\nbb\nabc' ]]
printf 'print("x".replace("", "y"))\n' > s3b.nift
if "$NIFT" run s3b.nift >/dev/null 2>&1; then echo "empty replace succeeded" >&2; exit 1; fi

# --- Strict numeric conversion. ---
cat > s4.nift <<'NIFT'
print("42".to_int() + 1)
print("-42".to_int())
print("9223372036854775807".to_int())
print("+42".to_int())
print("3.5".to_double() + 1)
print("1e6".to_double())
print("42".to_double())
print(" 42 ".trim().to_int())
NIFT
[[ "$("$NIFT" run s4.nift)" == $'43\n-42\n9223372036854775807\n42\n4.5\n1000000\n42\n42' ]]
for expr in '" 42 ".to_int()' '"42x".to_int()' '"3.14".to_int()' '"0x10".to_double()' '"0x1p3".to_double()' '"1e999".to_double()' '"nan".to_double()' '"3.2x".to_double()' '"+9223372036854775808".to_int()' '"" .to_int()'; do :; done
for expr in '" 42 ".to_int()' '"42x".to_int()' '"3.14".to_int()' '"0x10".to_double()' '"1e999".to_double()' '"nan".to_double()' '"3.2x".to_double()' '"+9223372036854775808".to_int()'; do
  printf 'print(%s)\n' "$expr" > s4b.nift
  if "$NIFT" run s4b.nift >/dev/null 2>&1; then echo "expected failure: $expr" >&2; exit 1; fi
done

# --- Numeric to_string is canonical (no trailing zeros). ---
cat > s5.nift <<'NIFT'
print(42.to_string())
print((-17).to_string())
print(3.14.to_string())
print(1.0.to_string())
print(100.5.to_string())
print(9223372036854775807.to_string())
print(42.stringify())
NIFT
[[ "$("$NIFT" run s5.nift)" == $'42\n-17\n3.14\n1\n100.5\n9223372036854775807\n42' ]]

# --- Expression-valued arrays: left-to-right, exactly once, nested. ---
cat > s6.nift <<'NIFT'
i := 0
a := [i++, i++, i++]
print(a.stringify())
print(i)
n := 0
fn(next()) { n += 1
return n }
b := [next(), next(), next()]
print(b.stringify())
print(n)
x := 5
c := [x, x + 1, "6".to_int(), [x * 2, x * 3]]
print(c.stringify())
NIFT
[[ "$("$NIFT" run s6.nift)" == $'[0,1,2]\n3\n[1,2,3]\n3\n[5,6,6,[10,15]]' ]]

# --- Methods on literals / call results / chains; single receiver evaluation. ---
cat > s7.nift <<'NIFT'
print(" hello ".trim())
print("a,b".split(",").size())
print(["a","b"].join(",").to_upper())
print((1 + 2).to_string())
fn(g()) { return "  hi  " }
print(g().trim().to_upper())
print(" a,b,c ".trim().split(",").size())
print("42".trim().to_int().to_string())
count := 0
fn(tick()) { count += 1
return "  v  " }
print(tick().trim())
print(count)
NIFT
[[ "$("$NIFT" run s7.nift)" == $'hello\n2\nA,B\n3\nHI\n3\n42\nv\n1' ]]

# --- Prefix-recognizer adversarial: method chains inside larger expressions. ---
cat > s8.nift <<'NIFT'
print("a,b".split(",").size() + 1)
print((1 + 2).to_string() == "3")
print(" x ".trim().to_upper() == "X")
x := ["a", "b"]
print(x.join(",").length() + 1)
print(1 + "a,b".split(",").size())
NIFT
[[ "$("$NIFT" run s8.nift)" == $'3\ntrue\ntrue\n4\n3' ]]

# --- Presentation composition is preserved alongside the new methods. ---
cat > s9.nift <<'NIFT'
x := [1, 2]
print(x.prettify() == x.prettify().prettify())
print(x.prettify().highlight() == x.highlight().prettify())
print(x.highlight().prettify().highlight() == x.prettify().highlight())
print("a,b".split(",").stringify())
NIFT
[[ "$("$NIFT" run s9.nift)" == $'true\ntrue\ntrue\n["a","b"]' ]]