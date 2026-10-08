#!/usr/bin/env bash
# Independent black-box contract: `nift init --migration` initialization.
# Public behaviour only: fresh initialization creates the migration scaffold
# (MIGRATION.md, HANDOVER.md, README.md, AGENTS.md with one Nift-managed block,
# and investigation/ with the operational records); the default existing-file
# policy is fail-closed for canonical docs and non-destructive for
# README/guidance; keep and replace policies behave as documented; AGENTS
# augmentation is idempotent; the generated scaffold is deterministic.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; cd "$t"

# Fresh migration initialization.
mkdir -p fresh
( cd fresh && "$NIFT_BIN" init --migration >/dev/null 2>err ) || { echo "init --migration failed: $(cat err)" >&2; exit 1; }
for f in MIGRATION.md HANDOVER.md AGENTS.md README.md; do
  [ -f "fresh/$f" ] || { echo "missing fresh/$f" >&2; exit 1; }
done
for f in README.md STATUS.md BASELINE.md EXTERNAL-INPUTS.md KNOWN-DIVERGENCES.md PARITY-CONTRACT.md; do
  [ -f "fresh/investigation/$f" ] || { echo "missing fresh/investigation/$f" >&2; exit 1; }
done
[ "$(grep -c 'nift:migration:start' fresh/AGENTS.md)" = 1 ] || { echo "AGENTS.md missing exactly one managed block" >&2; exit 1; }

# The scaffold distinguishes reference from migration output and records the
# source model and the compatibility gate.
grep -q 'REFERENCE OUTPUT' fresh/investigation/BASELINE.md || { echo "BASELINE.md lacks reference/output distinction" >&2; exit 1; }
grep -q 'Source model' fresh/investigation/BASELINE.md || { echo "BASELINE.md lacks source model" >&2; exit 1; }
grep -q 'compatibility proof must precede broad content translation' fresh/investigation/STATUS.md || { echo "STATUS.md lacks gate" >&2; exit 1; }

# Islands inform architecture proof; profiling and revalidation precede final timing.
python3 - fresh <<'PY_GUIDANCE'
from pathlib import Path
import sys
root = Path(sys.argv[1])
method = (root / "MIGRATION.md").read_text()
status = (root / "investigation/STATUS.md").read_text()
assert method.index("Interactive islands and client frameworks") < method.index("### Phase 3")
for item in ("React", "Vue", "Svelte", "Solid", "Web Components", "vanilla JavaScript",
             "independently prepared browser-side", "benchmark-specific special cases"):
    assert item in method, f"missing public migration guidance: {item}"
for text, labels in ((method, ("### Phase 7", "### Phase 9 - Performance campaign",
                              "### Phase 10 - Final parity revalidation", "### Phase 11 - Final benchmark campaign")),
                     (status, ("| 7 Route/content", "| 9 Performance campaign",
                               "| 10 Final parity revalidation", "| 11 Final benchmark campaign"))):
    positions = [text.index(label) for label in labels]
    assert positions == sorted(positions), "public migration checkpoint order changed"
PY_GUIDANCE

# Deterministic scaffold.
mkdir -p fresh2
( cd fresh2 && "$NIFT_BIN" init --migration >/dev/null 2>&1 )
for f in README.md investigation/STATUS.md investigation/BASELINE.md; do
  cmp -s "fresh/$f" "fresh2/$f" || { echo "nondeterministic $f" >&2; exit 1; }
done

# Marker form is the deterministic ownership boundary.
grep -q '<!-- nift:migration:start -->' fresh/AGENTS.md || { echo "AGENTS block start marker missing" >&2; exit 1; }
grep -q '<!-- nift:migration:end -->' fresh/AGENTS.md || { echo "AGENTS block end marker missing" >&2; exit 1; }

# Plain init must not create migration files.
mkdir -p plain
( cd plain && "$NIFT_BIN" init >/dev/null 2>&1 )
[ -f plain/MIGRATION.md ] && { echo "plain init created MIGRATION.md" >&2; exit 1; }
[ -f plain/AGENTS.md ] && { echo "plain init created AGENTS.md" >&2; exit 1; }

# Default existing-file policy: fail closed for canonical docs, list conflict,
# preserve the file, and leave no project behind.
mkdir -p conflict
printf 'keep me\n' > conflict/HANDOVER.md
if ( cd conflict && "$NIFT_BIN" init --migration >/dev/null 2>err ); then echo "conflict accepted" >&2; exit 1; fi
grep -q 'HANDOVER.md already exists' conflict/err || { echo "no conflict listing: $(cat conflict/err)" >&2; exit 1; }
[ "$(cat conflict/HANDOVER.md)" = "keep me" ] || { echo "conflicting file was modified" >&2; exit 1; }
[ -f conflict/.nift/config.json ] && { echo "partial project left behind" >&2; exit 1; }

# Non-canonical guidance (README) is non-destructive: an existing README is kept
# and does not abort the default run.
mkdir -p readme
printf '# my project\n' > readme/README.md
( cd readme && "$NIFT_BIN" init --migration >/dev/null 2>&1 )
[ "$(cat readme/README.md)" = "# my project" ] || { echo "existing README overwritten" >&2; exit 1; }
[ -f readme/MIGRATION.md ] || { echo "existing README blocked scaffold" >&2; exit 1; }

# One explicit preserve policy (keep): existing file untouched, missing files created.
mkdir -p keep
printf 'mine\n' > keep/MIGRATION.md
( cd keep && "$NIFT_BIN" init --migration --migration-existing=keep >/dev/null 2>&1 )
[ "$(cat keep/MIGRATION.md)" = "mine" ] || { echo "keep modified MIGRATION.md" >&2; exit 1; }
[ -f keep/HANDOVER.md ] || { echo "keep did not create HANDOVER.md" >&2; exit 1; }

# AGENTS augmentation is idempotent: pre-existing unrelated content is kept and
# exactly one managed block remains after rerunning on a pre-marked file.
mkdir -p idem
printf '# my agents\n\n<!-- nift:migration:start -->\n## Nift migration\nold\n<!-- nift:migration:end -->\n\ntail\n' > idem/AGENTS.md
( cd idem && "$NIFT_BIN" init --migration --migration-existing=keep >/dev/null 2>&1 )
grep -q 'my agents' idem/AGENTS.md || { echo "AGENTS unrelated content lost" >&2; exit 1; }
grep -q 'tail' idem/AGENTS.md || { echo "AGENTS trailing content lost" >&2; exit 1; }
[ "$(grep -c 'nift:migration:start' idem/AGENTS.md)" = 1 ] || { echo "AGENTS block duplicated" >&2; exit 1; }

# Whitespace hygiene of the generated scaffold (when git is available).
if command -v git >/dev/null 2>&1; then
  ( cd fresh && git init -q && git add -A && git diff --cached --check ) || { echo "scaffold has whitespace errors" >&2; exit 1; }
fi

printf 'PASS v4.8 migration initialization\n'