#!/usr/bin/env bash
# Independent black-box contract: v4.6 recoverable operational errors and
# structured diagnostics. Operational failures are catchable with a structured
# Error (code/category/source/line/message/cause); programmer, arithmetic,
# policy and invalid-schema failures remain fatal and cannot be caught.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; cd "$t"

# Structured Error value shape and field propagation.
out=$("$NIFT_BIN" -e '
cause := error("root", "user.root")
value := error("outer", "user.owner.failed", cause)
print(type(value)); print(value.message); print(value.code); print(value.category)
print(value.source == ""); print(value.cause.message)
try { throw value } catch(err) {
  print(err.source != ""); print(err.line > 0); print(err.column > 0)
  try { throw err } catch(again) { print(again.line == err.line) }
}')
[ "$out" = $'error\nouter\nuser.owner.failed\nuser\ntrue\nroot\ntrue\ntrue\ntrue\ntrue' ] || { echo "error shape: $out" >&2; exit 1; }

# Only user.* codes are constructible; builtin operational namespaces are not.
for expr in 'error("x", "io.open_failed")' 'error("x", "user.Upper")' 'error("x", "user")' 'error("x", "user.a", 1)'; do
  if "$NIFT_BIN" eval "$expr" >/dev/null 2>&1; then echo "bad constructor accepted: $expr" >&2; exit 1; fi
done

# Fatal classes bypass catch even inside try.
fatal(){
  if "$NIFT_BIN" -e "try { $1 } catch(e) { print(\"CAUGHT\") }" >"$t/o" 2>"$t/e"; then
    echo "fatal unexpectedly succeeded: $1" >&2; exit 1
  fi
  grep -q CAUGHT "$t/o" && { echo "fatal was caught: $1" >&2; exit 1; } || true
}
fatal 'value := 1 / 0'
fatal 'open(42)'
fatal 'validate(1)'

# Operational filesystem failures are recoverable with a structured outcome.
check_code(){ # <expected-code> <operation>
  local out
  out=$("$NIFT_BIN" -e "try { $2 } catch(err) { print(err.code + \"|\" + err.category + \"|\" + (err.source != \"\") + \"|\" + (err.line > 0) + \"|\" + err.message) }")
  case "$out" in "$1|"*) : ;; *) echo "expected $1 for $2, got: $out" >&2; exit 1 ;; esac
}
check_code io.open_failed 'open("missing.txt")'
check_code io.open_failed 'cat("missing.txt")'
check_code io.open_failed 'open_bytes("missing.bin")'
check_code io.create_failed 'touch("no-parent/x.txt")'

# JSON schema rejection is recoverable; an invalid schema type is fatal.
out=$("$NIFT_BIN" -e 'try { validate({"type":"string"}, 42) } catch(e) { print(e.code); print(e.category); print(e.source != ""); print(e.line > 0) }')
[ "$out" = $'schema.rejected\nschema\ntrue\ntrue' ] || { echo "schema rejection: $out" >&2; exit 1; }
fatal 'validate({"type":"banana"}, 1)'

# Import-source acquisition failure is recoverable.
out=$("$NIFT_BIN" -e 'try { import("./missing-file.f") } catch(e) { print(e.code); print(e.category); print(e.source != ""); print(e.line > 0) }')
[ "$out" = $'io.import_source_unreadable\nio\ntrue\ntrue' ] || { echo "import source failure: $out" >&2; exit 1; }

# Uncaught operational failure preserves the human message and leaks no
# structured keys into stderr.
if "$NIFT_BIN" -e 'open("missing.txt")' >"$t/o" 2>"$t/e"; then echo "open unexpectedly succeeded" >&2; exit 1; fi
grep -q 'cannot open path' "$t/e"
grep -qE '"code"|"category"|"cause"' "$t/e" && { echo "structured keys leaked to stderr" >&2; exit 1; } || true

# FFI loader and symbol failures are recoverable operational errors.
out=$("$NIFT_BIN" -e 'try { ffi_open("no-such-library-xyz.so") } catch(e) { print(e.code); print(e.category); print(e.source != ""); print(e.line > 0) }')
[ "$out" = $'ffi.library_load_failed\nffi\ntrue\ntrue' ] || { echo "ffi load failure: $out" >&2; exit 1; }
CC=${CC:-cc}
case "$(uname -s)" in Darwin) EXT=dylib ;; MINGW*|MSYS*|CYGWIN*) EXT=dll ;; *) EXT=so ;; esac
if printf 'int contract_placeholder(void){return 0;}\n' > fx.c && "$CC" -std=c99 -fPIC -shared fx.c -o "libfx.$EXT" 2>/dev/null; then
  out=$("$NIFT_BIN" -e "try { lib := ffi_open(\"$PWD/libfx.$EXT\"); ffi_call(lib, \"no_such_symbol_xyz\", \"i64(i64)\", 1) } catch(e) { print(e.code); print(e.category) }")
  [ "$out" = $'ffi.symbol_not_found\nffi' ] || { echo "ffi symbol failure: $out" >&2; exit 1; }
fi

# Worker/future recoverable failures replay on repeated join/await.
out=$("$NIFT_BIN" -e '
fn(fail()) { throw error("call", "user.call") }
fn[async](async_fail()) { throw error("future", "user.future") }
future := async_fail()
try { await future } catch(err) { print(err.code) }
try { await future } catch(err) { print(err.message) }
t := thread(fail)
try { t.join() } catch(err) { print(err.code) }
try { t.join() } catch(err) { print(err.message) }')
[ "$out" = $'user.future\nfuture\nuser.call\ncall' ] || { echo "worker error replay: $out" >&2; exit 1; }

# Failed import rolls back its registrations before the importer's catch runs.
cat > rollback.f <<'F'
leaked := stack()
fn(leaked_callable()) { return 1 }
export(leaked_callable)
throw error("module failed", "user.module")
F
cat > importer.f <<'F'
try { import("./rollback.f") } catch(err) { print(err.code) }
fn(leaked_callable()) { return 2 }
print(leaked_callable())
F
out=$("$NIFT_BIN" importer.f)
[ "$out" = $'user.module\n2' ] || { echo "import rollback: $out" >&2; exit 1; }

printf 'PASS v4.6 recoverable errors\n'
