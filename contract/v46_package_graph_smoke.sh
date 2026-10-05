#!/usr/bin/env bash
# Independent black-box contract: v4.6 deterministic package graph. A real add
# emits a v2 graph lock with local provenance; read-only imports do not rewrite
# it; `nift packages` explains the graph in human and JSON form; remove/install
# mutate the lock deterministically; cycles and missing nodes are rejected.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; cd "$t"

mk_pkg(){ # <dir> <name> [dependencies-json]
  mkdir -p "$1/src"
  if [ -n "${3:-}" ]; then
    printf '{"name":"%s","version":"0.1.0","entry":"src/main.f","dependencies":%s}\n' "$2" "$3" > "$1/manifest.json"
  else
    printf '{"name":"%s","version":"0.1.0","entry":"src/main.f"}\n' "$2" > "$1/manifest.json"
  fi
  printf 'fn(%s_hello()) { return 42 }\nexport(%s_hello)\n' "$2" "$2" > "$1/src/main.f"
}

mk_pkg pkg demo
mkdir -p site/.nift
(cd site && "$NIFT_BIN" add ../pkg >/dev/null)
grep -q '"lockfileVersion": 2' site/.nift/packages.lock.json
grep -q '"commit": "local"' site/.nift/packages.lock.json

# A read-only import does not rewrite the lock.
lock_before=$(cksum site/.nift/packages.lock.json)
printf '@import("demo")\nprint(demo_hello())\n' > site/main.f
[ "$(cd site && "$NIFT_BIN" main.f)" = '42' ] || { echo "package import failed" >&2; exit 1; }
[ "$(cksum site/.nift/packages.lock.json)" = "$lock_before" ] || { echo "read-only import rewrote lock" >&2; exit 1; }

# Human graph explanation.
graph=$(cd site && "$NIFT_BIN" packages)
case "$graph" in *'demo'*) : ;; *) echo "packages missing node: $graph" >&2; exit 1 ;; esac
case "$graph" in *'required by:'*) : ;; *) echo "packages missing provenance" >&2; exit 1 ;; esac

# JSON query shape (distinct from the lock: uses "paths").
json=$(cd site && "$NIFT_BIN" packages --json)
case "$json" in *'"lockfileVersion": 2'*'"paths"'*'"nodes"'*) : ;; *) echo "bad packages --json: $json" >&2; exit 1 ;; esac

# Unknown node is a controlled error.
if (cd site && "$NIFT_BIN" packages zz >/dev/null 2>"$t/e"); then echo "unknown node accepted" >&2; exit 1; fi
grep -q 'package is not in the dependency graph: zz' "$t/e"

# Remove drops the dependency and rewrites the lock (no stdout).
out=$(cd site && "$NIFT_BIN" remove demo)
[ -z "$out" ] || { echo "remove produced stdout: $out" >&2; exit 1; }
grep -q '"demo"' site/manifest.json && { echo "remove left dependency" >&2; exit 1; } || true

# Reinstall from a v1 (legacy direct-only) lock migrates to v2.
mkdir -p v1site/.nift/packages/demo
printf '{"dependencies":{"demo":{"source":"../pkg","ref":"local"}}}\n' > v1site/manifest.json
printf '{"demo":{"source":"../pkg","requested":"local","commit":"local"}}\n' > v1site/.nift/packages.lock.json
(cd v1site && "$NIFT_BIN" install >/dev/null)
grep -q '"lockfileVersion": 2' v1site/.nift/packages.lock.json

# Deterministic transitive graph: a shared dependency reached through two
# parents yields two distinct, order-stable paths.
mk_pkg pkgs/shared shared
mk_pkg pkgs/alpha alpha '{"shared":{"source":"../shared","ref":"local"}}'
mk_pkg pkgs/beta beta '{"shared":{"source":"../shared","ref":"local"}}'
mkdir -p diamond/.nift
(cd diamond && "$NIFT_BIN" add ../pkgs/alpha >/dev/null && "$NIFT_BIN" add ../pkgs/beta >/dev/null)
graph=$(cd diamond && "$NIFT_BIN" packages shared)
case "$graph" in *'alpha -> shared'*'beta -> shared'*) : ;; *) echo "transitive graph: $graph" >&2; exit 1 ;; esac
grep -q '"shared"' diamond/.nift/packages.lock.json
grep -q '"alpha"' diamond/.nift/packages.lock.json

# A self-referential package graph is rejected.
mk_pkg selfcyc selfcyc '{"selfcyc":{"source":"./selfcyc","ref":"local"}}'
mkdir -p cycsite/.nift
if (cd cycsite && "$NIFT_BIN" add ../selfcyc >/dev/null 2>&1); then
  echo "self-cycle package unexpectedly installed" >&2; exit 1
fi

printf 'PASS v4.6 package graph\n'
