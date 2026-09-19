#!/usr/bin/env bash
# Independent black-box contract for v4.4 restrictions: --no-process must
# deny every script-reachable process surface (run, cmd pipeline, shell
# fallback, eval, build hooks) while keeping Nift-native filesystem
# operations available, and the opt-in filesystem-root restriction must
# confine Nift-native filesystem operations. These are NOT claimed to be an
# OS sandbox.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
out=$(printf 'printf hello\nexit\n' | "$NIFT_BIN" sh --no-process 2>&1 || true)
grep -q 'external process execution disabled' <<<"$out"
cat >"$t/bypass.f" <<'F'
p := cmd("echo", "BYPASS").run()
print(p.stdout)
F
if NIFT_NO_PROCESS=1 "$NIFT_BIN" run "$t/bypass.f" >"$t/o" 2>&1; then exit 1; fi
grep -q 'external process execution disabled' "$t/o"
if NIFT_NO_PROCESS=1 "$NIFT_BIN" eval 'run("echo","x").stdout' >"$t/o2" 2>&1; then exit 1; fi
grep -q 'external process execution disabled' "$t/o2"
mkdir -p "$t/site/.nift" "$t/site/content" "$t/site/templates" "$t/site/public" "$t/site/scripts"
printf '{"config":{"content-dir":"content/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/main.html","pre build":"scripts/h.f"}}\n' > "$t/site/.nift/config.json"
printf '{"tracked":[{"name":"/","title":"Home","template":"templates/main.html"}]}\n' > "$t/site/.nift/tracked.json"
printf 'x\n' > "$t/site/content/index.html"
printf '<div>@content</div>\n' > "$t/site/templates/main.html"
printf 'r := run("echo","hi")\n' > "$t/site/scripts/h.f"
hb=$(cd "$t/site" && "$NIFT_BIN" build --all --no-process 2>&1 || true)
grep -q 'external process execution disabled' <<<"$hb"
cat >"$t/native.f" <<F
touch("$t/ok.txt")
print(exists("$t/ok.txt"))
F
[ "$("$NIFT_BIN" run "$t/native.f" --no-process)" = "true" ]
mkdir -p "$t/root" "$t/root/inner"
printf 'in\n' > "$t/root/inner/ok.txt"
cat >"$t/root/inner/t.f" <<'F'
print(open("ok.txt"))
F
[ "$(cd "$t/root/inner" && "$NIFT_BIN" run t.f --fs-root="$t/root/inner")" = "in" ]
cat >"$t/root/inner/escape.f" <<F
print(touch("$t/root/escape-target"))
F
if (cd "$t/root/inner" && "$NIFT_BIN" run escape.f --fs-root="$t/root/inner") >"$t/e" 2>&1; then exit 1; fi
grep -q 'escapes configured filesystem root' "$t/e"
printf 'PASS v4.4 restricted mode\n'