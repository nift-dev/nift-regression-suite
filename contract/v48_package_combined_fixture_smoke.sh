#!/usr/bin/env bash
# Nift package-system machinery with controlled synthetic fixtures: two local
# packages (a facade struct plus a package-private helper each) install and
# import together; both facades resolve and neither package's private helper
# leaks into the importer. This preserves the combined-import machinery that
# the former real-package curl+sqlite/vips+magick contracts also exercised,
# without depending on any real package API (see packages-regression-suite for
# ecosystem-level package contracts).
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/alpha/src" "$t/beta/src" "$t/site/.nift"
printf '{"name":"alpha","version":"0.1.0","entry":"src/main.f"}\n' > "$t/alpha/manifest.json"
cat > "$t/alpha/src/main.f" <<'F'
fn(alpha_helper(x)) { return x * 2 }
alpha := {"double": (x) => { return alpha_helper(x) + 1 } }
export(alpha)
F
printf '{"name":"beta","version":"0.1.0","entry":"src/main.f"}\n' > "$t/beta/manifest.json"
cat > "$t/beta/src/main.f" <<'F'
fn(beta_helper(x)) { return x + 3 }
beta := {"triple": (x) => { return beta_helper(x) * 2 } }
export(beta)
F
(cd "$t/site" && "$NIFT_BIN" add "$t/alpha" >/dev/null 2>&1)
(cd "$t/site" && "$NIFT_BIN" add "$t/beta" >/dev/null 2>&1)
cat > "$t/site/t.f" <<'F'
@import("alpha")
@import("beta")
print(alpha.double(4))
print(beta.triple(5))
F
[ "$(cd "$t/site" && "$NIFT_BIN" t.f)" = $'9\n16' ] || exit 1
for pair in "alpha alpha_helper" "beta beta_helper"; do
  set -- $pair
  printf '@import("%s")\nprint(%s)\n' "$1" "$2" > "$t/site/p.f"
  if (cd "$t/site" && "$NIFT_BIN" p.f >/dev/null 2>&1); then echo "private helper leaked: $1.$2" >&2; exit 1; fi
done
printf 'PASS v4.8 synthetic combined package fixture\n'