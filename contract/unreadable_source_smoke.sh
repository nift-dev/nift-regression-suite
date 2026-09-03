#!/usr/bin/env bash
# Black-box unreadable-source contract. A tracked content file, an @input
# file, or a template that becomes unreadable must fail the build with a clear
# "not readable" diagnostic and must leave the previously successful output and
# page metadata byte-identical. An empty-but-readable source remains a valid,
# distinct state and must build successfully. These are render-time failures
# (the read is the authority), so they preserve the last-good output.
set -u
NIFT_BIN="${NIFT_BIN:-$(pwd)/nift}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nift-ur-contract.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export NIFT_BIN TMP

# On platforms where a chmod-000 file remains readable by the current user
# (e.g. Windows), the unreadable cases cannot be exercised. The module then
# reports an explicit skip and exits successfully; it is not a failure. Linux
# is the evidence platform for the chmod-based cases.
if ! python3 - <<'PY'
import os, pathlib, tempfile, sys
with tempfile.TemporaryDirectory() as td:
    p = pathlib.Path(td) / "probe"
    p.write_text("x")
    os.chmod(p, 0)
    try:
        with open(p) as f: f.read()
        sys.exit(1)  # still readable: platform cannot enforce unreadable
    except PermissionError:
        sys.exit(0)
PY
then
  echo "unreadable-source contract SKIPPED: platform cannot enforce chmod-000 unreadability"
  exit 0
fi

python3 - <<'PY'
import json, os, pathlib, subprocess, sys
root = pathlib.Path(os.environ['TMP']) / 'project'
nift = os.environ['NIFT_BIN']

def fail(msg):
    print('unreadable-source FAIL:', msg, file=sys.stderr)
    sys.exit(1)

def scaffold():
    root.mkdir()
    (root / '.nift').mkdir(); (root / 'content').mkdir(); (root / 'templates').mkdir(); (root / 'public').mkdir()
    (root / '.nift/config.json').write_text(json.dumps({'config': {
        'content-dir': 'content/', 'content-ext': '.html', 'output-dir': 'public/', 'output-ext': '.html',
        'default-template': 'templates/template.html', 'build-threads': 1, 'incremental-mode': 'modified',
        'minify-exts': []}}))
    (root / '.nift/tracked.json').write_text(json.dumps({'tracked': [
        {'name': '/', 'title': 'Home', 'template': 'templates/template.html'}]}))
    (root / 'templates/template.html').write_text('<main>@content</main>\n')
    (root / 'content/index.html').write_text('<p>BASE</p>\n')
    subprocess.run([nift, 'build', '--all'], cwd=root, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

def pair():
    return (root / 'public/index.html').read_bytes(), (root / '.nift/public/index.info.json').read_bytes()

def expect_not_readable(prior, label, restore):
    p = subprocess.run([nift, 'build', '--all'], cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode == 0:
        fail(label + ': build unexpectedly succeeded')
    if 'not readable' not in (p.stdout + p.stderr):
        fail(label + ': missing "not readable" diagnostic: ' + (p.stdout + p.stderr)[:200])
    now = pair()
    if now != prior:
        fail(label + ': previously successful output/metadata changed after failed build')
    os.chmod(restore, 0o644)

scaffold()

# 1. Unreadable tracked content.
prior = pair()
(root / 'content/index.html').write_text('<p>NEW</p>\n')
os.chmod(root / 'content/index.html', 0)
expect_not_readable(prior, 'unreadable content', root / 'content/index.html')

# 2. Unreadable @input source.
(root / 'templates/template.html').write_text('<head>@input("templates/head.html")</head><main>@content</main>\n')
(root / 'templates/head.html').write_text('<meta charset="utf-8">\n')
subprocess.run([nift, 'build', '--all'], cwd=root, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
prior = pair()
(root / 'templates/head.html').write_text('<link>new</link>\n')
os.chmod(root / 'templates/head.html', 0)
expect_not_readable(prior, 'unreadable @input', root / 'templates/head.html')

# 3. Unreadable template (must give the template-readable diagnostic, not the
#    downstream "@content exactly once" error).
(root / 'templates/template.html').write_text('<section>@content</section>\n')
subprocess.run([nift, 'build', '--all'], cwd=root, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
prior = pair()
os.chmod(root / 'templates/template.html', 0)
p = subprocess.run([nift, 'build', '--all'], cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
if p.returncode == 0:
    fail('unreadable template: build unexpectedly succeeded')
if 'template file is not readable' not in (p.stdout + p.stderr):
    fail('unreadable template: wrong diagnostic: ' + (p.stdout + p.stderr)[:200])
if pair() != prior:
    fail('unreadable template: previously successful output/metadata changed')
os.chmod(root / 'templates/template.html', 0o644)

# 4. Empty-but-readable vs unreadable remain distinct.
(root / 'templates/template.html').write_text('<main>@content</main>\n')
(root / 'content/index.html').write_text('')
subprocess.run([nift, 'build', '--all'], cwd=root, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
if (root / 'public/index.html').read_text() != '<main></main>\n':
    fail('empty readable content rendered wrong')
prior = pair()
os.chmod(root / 'content/index.html', 0)
expect_not_readable(prior, 'empty-but-unreadable content', root / 'content/index.html')

print('unreadable-source contract passed')
PY