#!/usr/bin/env bash
# Independent black-box contract: v4.6 first-class immutable bytes. Construction,
# accessors, concatenation, slicing, equality, UTF-8 decode, shared identity
# across assignment/copy/closure/threads/async, byte I/O round-trips, and the
# documented rejection boundaries (no text rendering, no serialization).
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; cd "$t"

out=$("$NIFT_BIN" -e 'b := bytes([0,65,127,128,255]); print(type(b)); print(is_bytes(b)); print(b.length()); print(b.size()); print(b[1]); print(b?[1]); print(b.slice(1,4)[2]); print((b + bytes([1])).length()); print(b == bytes([0,65,127,128,255])); print(b != bytes([0])); print(b != [0,65,127,128,255]); print(b != ""); print(!bytes()); print(!b); u := bytes([195,169,240,159,152,128]); print(u.decode("utf-8").encode("utf-8") == u)')
[ "$out" = $'bytes\ntrue\n5\n5\n65\n65\n128\n6\ntrue\ntrue\ntrue\ntrue\ntrue\nfalse\ntrue' ] || { echo "bytes accessor output: $out" >&2; exit 1; }

reject(){ # <stderr-substring> <program>
  if "$NIFT_BIN" -e "$2" >/dev/null 2>"$t/e"; then echo "unexpectedly accepted: $2" >&2; exit 1; fi
  grep -q "$1" "$t/e" || { echo "missing '$1' for: $2" >&2; cat "$t/e" >&2; exit 1; }
}
reject '0 to 255'              'bytes([-1])'
reject '0 to 255'              'bytes([256])'
reject 'array of integers'     'bytes("x")'
reject 'cannot be rendered'    'print(bytes([65]))'
reject 'not serializable'      '[1,{"x":bytes([2])}].stringify()'
reject 'not serializable'      'bytes([1]).prettify()'
reject 'not supported'         'bytes([1]) < bytes([2])'
reject 'invalid UTF-8'         'bytes([226,40,161]).decode("utf-8")'
reject 'invalid UTF-8'         'bytes([192,128]).decode("utf-8")'

# The expression evaluator refuses bytes values (serialization boundary).
if "$NIFT_BIN" eval '[bytes([1])]' >/dev/null 2>"$t/e"; then echo "eval accepted bytes" >&2; exit 1; fi
grep -q 'bytes values are not serializable' "$t/e"

# Shared identity across copy, closure, thread and async transfer.
cat > transfer.nift <<'F'
fn(prepared_identity(x)) { return x }
fn(make_closure(x)) { local := x; result := () => local; return result }
fn(thread_identity(x)) { return x }
@fn[async](async_identity(x)) { return x }
source := bytes([0,17,127,128,254,255])
copied := copy(source)
closure := make_closure(source)
t := thread(thread_identity, source)
f := async_identity(source)
print(copied == source)
print(closure() == source)
print(t.join() == source)
print((await f) == source)
aggregate := {"payload":[source], "marker":1}
deep := deepcopy(aggregate)
deep["marker"] = 2
deep["payload"][0] = bytes([9])
print(aggregate.marker); print(deep.marker)
print(aggregate.payload[0] == source)
m := mutex({"payload":source, "marker":1})
m.lock(); mv := m.get(); mv["marker"] = 8; mv["payload"] = bytes([8])
print(m.get().marker); print(m.get().payload == source); m.unlock()
F
out=$("$NIFT_BIN" transfer.nift)
[ "$out" = $'true\ntrue\ntrue\ntrue\n1\n2\ntrue\n1\ntrue' ] || { echo "bytes transfer output: $out" >&2; exit 1; }

# Byte I/O round-trip: open_bytes, stream read_bytes, exact raw writes.
printf '\000\101\200\377\132' > input.bin
cat > io.nift <<'F'
b := open_bytes("input.bin")
print(type(b)); print(b.length()); print(b[0]); print(b[2]); print(b[4])
i := ifstream("input.bin")
a := i.read_bytes(2)
rest := i.read_all_bytes()
print(a.length()); print(a[0]); print(a[1]); print(rest.length())
close(i)
o := ofstream("out.bin")
o.write(a); o.write(rest); close(o)
print(open_bytes("out.bin") == b)
F
out=$("$NIFT_BIN" io.nift)
[ "$out" = $'bytes\n5\n0\n128\n90\n2\n0\n65\n3\ntrue' ] || { echo "byte I/O output: $out" >&2; exit 1; }
cmp -s input.bin out.bin || { echo "byte round-trip mismatch" >&2; exit 1; }

# Missing/invalid byte reads are recoverable.
"$NIFT_BIN" -e 'try { open_bytes("missing.bin") } catch(e) { print(e.code); print(e.category) }' >"$t/o"
grep -qx 'io.open_failed' "$t/o"
grep -qx 'io' "$t/o"

printf 'PASS v4.6 bytes\n'
