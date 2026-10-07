#!/usr/bin/env bash
# Independent black-box contract: `nift init --migration` initialization.
# Public behaviour only: fresh initialization creates MIGRATION.md, HANDOVER.md,
# AGENTS.md (with one Nift-managed migration block) and investigation/; the
# default existing-file policy is fail-closed and non-destructive; keep and
# replace policies behave as documented; AGENTS augmentation is idempotent.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; cd "$t"

# Fresh migration initialization.
mkdir -p fresh
( cd fresh && "$NIFT_BIN" init --migration >/dev/null 2>err ) || { echo "init --migration failed: $(cat err)" >&2; exit 1; }
for f in MIGRATION.md HANDOVER.md AGENTS.md; do
  [ -f "fresh/$f" ] || { echo "missing fresh/$f" >&2; exit 1; }
done
[ -d fresh/investigation ] || { echo "missing investigation/" >&2; exit 1; }
[ "$(grep -c 'nift:migration:start' fresh/AGENTS.md)" = 1 ] || { echo "AGENTS.md missing exactly one managed block" >&2; exit 1; }

# Marker form is the deterministic ownership boundary.
grep -q '<!-- nift:migration:start -->' fresh/AGENTS.md || { echo "AGENTS block start marker missing" >&2; exit 1; }
grep -q '<!-- nift:migration:end -->' fresh/AGENTS.md || { echo "AGENTS block end marker missing" >&2; exit 1; }

# Plain init must not create migration files.
mkdir -p plain
( cd plain && "$NIFT_BIN" init >/dev/null 2>&1 )
[ -f plain/MIGRATION.md ] && { echo "plain init created MIGRATION.md" >&2; exit 1; }
[ -f plain/AGENTS.md ] && { echo "plain init created AGENTS.md" >&2; exit 1; }

# Default existing-file policy: fail closed, list conflict, preserve the file,
# and leave no project behind.
mkdir -p conflict
printf 'keep me\n' > conflict/HANDOVER.md
if ( cd conflict && "$NIFT_BIN" init --migration >/dev/null 2>err ); then echo "conflict accepted" >&2; exit 1; fi
grep -q 'HANDOVER.md already exists' conflict/err || { echo "no conflict listing: $(cat conflict/err)" >&2; exit 1; }
[ "$(cat conflict/HANDOVER.md)" = "keep me" ] || { echo "conflicting file was modified" >&2; exit 1; }
[ -f conflict/.nift/config.json ] && { echo "partial project left behind" >&2; exit 1; }

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

printf 'PASS v4.8 migration initialization\n'