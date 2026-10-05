#!/usr/bin/env bash
# Independent black-box contract: v4.6 strict package-metadata validation.
# Installable package identity requires name + version + entry; malformed,
# incomplete, unknown-field and unsafe manifests are rejected by `add`/import.
# A valid add produces a deterministic v2 lock with local provenance, and a
# malformed existing project manifest is never replaced.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; cd "$t"

mk_pkg(){ # <dir> <manifest-json> [body]
  mkdir -p "$1/src"
  printf '%s\n' "$2" > "$1/manifest.json"
  printf '%s\n' "${3:-value := 1\nexport(value)}" > "$1/src/main.f"
}

# Valid package: name+version+entry.
mk_pkg pkg '{"name":"demo","version":"0.1.0","entry":"src/main.f"}'
mkdir -p site/.nift
[ "$(cd site && "$NIFT_BIN" add ../pkg)" = 'added demo' ] || { echo "valid add failed" >&2; exit 1; }
grep -q '"lockfileVersion": 2' site/.nift/packages.lock.json
grep -q '"commit": "local"' site/.nift/packages.lock.json
grep -q '"demo"' site/manifest.json

# Invalid manifests are rejected.
mk_pkg bad-missing-version '{"name":"bad-missing-version","entry":"src/main.f"}'
mk_pkg bad-missing-name '{"version":"0.1.0","entry":"src/main.f"}'
mk_pkg bad-missing-entry '{"name":"bad-missing-entry","version":"0.1.0"}'
mk_pkg bad-entry-ext '{"name":"bad-entry-ext","version":"0.1.0","entry":"src/main.txt"}'
mk_pkg bad-unknown-field '{"name":"bad-unknown-field","version":"0.1.0","entry":"src/main.f","mystery":true}'
mk_pkg bad-backslash '{"name":"bad-backslash","version":"0.1.0","entry":"src\\main.f"}'
mk_pkg bad-version '{"name":"bad-version","version":"not-semver","entry":"src/main.f"}'
for p in bad-missing-version bad-missing-name bad-missing-entry bad-entry-ext bad-unknown-field bad-backslash bad-version; do
  d="site-$p"; mkdir -p "$d/.nift"
  if (cd "$d" && "$NIFT_BIN" add "../$p" >/dev/null 2>&1); then echo "invalid manifest accepted: $p" >&2; exit 1; fi
done

# A malformed existing project manifest is never replaced by add.
mkdir -p broken/.nift
printf '{broken\n' > broken/manifest.json
before=$(cksum broken/manifest.json)
if (cd broken && "$NIFT_BIN" add ../pkg >/dev/null 2>&1); then echo "add replaced malformed manifest" >&2; exit 1; fi
[ "$(cksum broken/manifest.json)" = "$before" ] || { echo "malformed manifest mutated" >&2; exit 1; }

# Dependency objects require both source and ref.
mkdir -p depsite/.nift
printf '{"dependencies":{"demo":{"source":"../pkg"}}}\n' > depsite/manifest.json
if (cd depsite && "$NIFT_BIN" install >/dev/null 2>&1); then echo "dependency missing ref accepted" >&2; exit 1; fi

# A hand-written valid local dependency installs and produces a complete v2 lock.
mkdir -p installsite/.nift
printf '{"dependencies":{"demo":{"source":"../pkg","ref":"local"}}}\n' > installsite/manifest.json
(cd installsite && "$NIFT_BIN" install >/dev/null)
grep -q '"lockfileVersion": 2' installsite/.nift/packages.lock.json
grep -q '"commit": "local"' installsite/.nift/packages.lock.json

# A package import requires a declared and locked dependency: a hand-placed
# package directory with a valid manifest but no lock entry cannot be imported.
mkdir -p nolock/.nift/packages/demo/src
printf '{"name":"demo","version":"0.1.0","entry":"src/main.f"}\n' > nolock/.nift/packages/demo/manifest.json
printf 'v := 1\nexport(v)\n' > nolock/.nift/packages/demo/src/main.f
printf '@import("demo")\nprint(v)\n' > nolock/t.f
if (cd nolock && "$NIFT_BIN" t.f >/dev/null 2>"$t/e"); then echo "unlocked package import accepted" >&2; exit 1; fi
grep -qE 'does not exist|package lock' "$t/e"

printf 'PASS v4.6 package metadata\n'
