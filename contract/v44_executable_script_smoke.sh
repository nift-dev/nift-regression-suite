#!/usr/bin/env bash
# Independent black-box contract: executable .f scripts follow the ordinary
# Unix model. nift script.f is a shorthand for direct nift script execution script.f (and what the
# shebang uses); ./script.f is ordinary OS process execution. Certifies the
# shebang chain, script arguments, command-style/run() from another script,
# permission failure (no fallback to direct nift script execution), --no-process, paths with
# spaces, Unicode, environment inheritance and path completion.
# POSIX-specific (executable bit/shebang); gated by the host platform.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
case "$NIFT_BIN" in /*) NIFT_ABS="$NIFT_BIN";; *) NIFT_ABS="$(pwd)/$NIFT_BIN";; esac
BIN="$(dirname "$NIFT_ABS")"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

cat > "$t/deploy.f" <<'F'
#!/usr/bin/env nift
print("deploy " + args.join(" "))
print("env=" + getenv("NIFT_CT_TEST"))
F
chmod +x "$t/deploy.f"

# nift script.f shorthand
out=$("$NIFT_ABS" "$t/deploy.f" staging --force)
[ "$(sed -n '1p' <<<"$out")" = "deploy staging --force" ] || { echo "$out" >&2; exit 1; }

# direct nift script execution of the same shebang file
out=$("$NIFT_ABS" "$t/deploy.f" one)
[ "$(sed -n '1p' <<<"$out")" = "deploy one" ] || exit 1

# ./script.f from the host shell (shebang; requires local nift on PATH)
out=$(cd "$t" && PATH="$BIN:$PATH" ./deploy.f a b)
[ "$(sed -n '1p' <<<"$out")" = "deploy a b" ] || { echo "$out" >&2; exit 1; }

# command-style from another script
cat > "$t/parent.f" <<'NIFT'
./deploy.f c d
NIFT
out=$(cd "$t" && PATH="$BIN:$PATH" "$NIFT_ABS" parent.f)
[ "$(sed -n '1p' <<<"$out")" = "deploy c d" ] || { echo "$out" >&2; exit 1; }

# run() structured invocation + exit code
cat > "$t/r.f" <<'NIFT'
r := run("./deploy.f", "e")
print("exit=" + r.exit_code.to_string())
NIFT
out=$(cd "$t" && PATH="$BIN:$PATH" "$NIFT_ABS" r.f)
[ "$(sed -n '1p' <<<"$out")" = "exit=0" ] || { echo "$out" >&2; exit 1; }

# executable permission failure: no fallback to direct nift script execution
chmod -x "$t/deploy.f"
if (cd "$t" && PATH="$BIN:$PATH" ./deploy.f >/dev/null 2>&1); then echo "exec -x succeeded" >&2; exit 1; fi
chmod +x "$t/deploy.f"

# --no-process blocks external execution (command-style and run())
cat > "$t/b1.f" <<'NIFT'
./deploy.f
NIFT
if (cd "$t" && PATH="$BIN:$PATH" NIFT_NO_PROCESS=1 "$NIFT_ABS" b1.f >/dev/null 2>&1); then echo "command-style not blocked" >&2; exit 1; fi
cat > "$t/b2.f" <<'NIFT'
run("./deploy.f")
NIFT
if (cd "$t" && PATH="$BIN:$PATH" NIFT_NO_PROCESS=1 "$NIFT_ABS" b2.f >/dev/null 2>&1); then echo "run() not blocked" >&2; exit 1; fi

# paths with spaces + Unicode
mkdir -p "$t/my dir" "$t/üni"
cp "$t/deploy.f" "$t/my dir/with space.f"
cp "$t/deploy.f" "$t/üni/child.f"
chmod +x "$t/my dir/with space.f" "$t/üni/child.f"
out=$(cd "$t" && PATH="$BIN:$PATH" ./my\ dir/with\ space.f sp)
[ "$(sed -n '1p' <<<"$out")" = "deploy sp" ] || { echo "$out" >&2; exit 1; }
out=$(cd "$t" && PATH="$BIN:$PATH" ./üni/child.f "héllo wörld")
[ "$(sed -n '1p' <<<"$out")" = "deploy héllo wörld" ] || { echo "$out" >&2; exit 1; }

# environment inheritance
out=$(cd "$t" && PATH="$BIN:$PATH" NIFT_CT_TEST="envval" "$NIFT_ABS" "$t/deploy.f" x)
[ "$(sed -n '2p' <<<"$out")" = "env=envval" ] || { echo "$out" >&2; exit 1; }

# non-zero child via shell child
printf '#!/bin/sh\nexit 3\n' > "$t/fail.sh"; chmod +x "$t/fail.sh"
cat > "$t/nz.f" <<'NIFT'
r := run("./fail.sh")
print("exit=" + r.exit_code.to_string())
NIFT
out=$(cd "$t" && PATH="$BIN:$PATH" "$NIFT_ABS" nz.f)
[ "$(sed -n '1p' <<<"$out")" = "exit=3" ] || { echo "$out" >&2; exit 1; }

# completion discovers ./paths (not .f-specific)
out=$(cd "$t" && "$NIFT_ABS" complete "./de")
[ "$out" = "./deploy.f" ] || { echo "$out" >&2; exit 1; }


# v4.5 certification of cmd/args/cwd/env and first-line-only shebang semantics.
cat > "$t/certify.f" <<'F'
#!/usr/bin/env nift
print(cmd)
print(args.join("|"))
print(pwd())
print(getenv("NIFT_CT_TEST"))
F
chmod +x "$t/certify.f"
out=$(cd "$t" && PATH="$BIN:$PATH" NIFT_CT_TEST=certified ./certify.f one two)
[ "$(sed -n '1p' <<<"$out")" = './certify.f' ]
[ "$(sed -n '2p' <<<"$out")" = 'one|two' ]
[ "$(sed -n '3p' <<<"$out")" = "$t" ]
[ "$(sed -n '4p' <<<"$out")" = 'certified' ]
cat > "$t/not-first.f" <<'F'
print("before")
#!/usr/bin/env nift
print("after")
F
[ "$("$NIFT_ABS" "$t/not-first.f")" = $'before\nafter' ]
cat > "$t/fail-shebang.f" <<'F'
#!/usr/bin/env nift
break
F
chmod +x "$t/fail-shebang.f"
! (cd "$t" && PATH="$BIN:$PATH" ./fail-shebang.f >/dev/null 2>&1)
case "$(uname -s)" in MINGW*|MSYS*) ;; *)
cat > "$t/signal.f" <<'F'
#!/usr/bin/env nift
i := 0
while(i < 1000000000) { i += 1 }
F
chmod +x "$t/signal.f"
(cd "$t"; PATH="$BIN:$PATH" ./signal.f >/dev/null 2>&1 & pid=$!; sleep 0.05; kill -TERM "$pid"; set +e; wait "$pid"; rc=$?; set -e; [ "$rc" -eq 143 ])
;; esac
echo 'PASS v4.5 executable script contract'
