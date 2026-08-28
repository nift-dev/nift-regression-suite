#!/usr/bin/env bash
set -euo pipefail
NIFT_BIN="${NIFT_BIN:-$(pwd)/nift}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nift-fs-recovery.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export NIFT_BIN TMP

python3 - <<'PY'
import json, os, pathlib, subprocess, time
root=pathlib.Path(os.environ['TMP'])/'project'
root.mkdir(); (root/'.nift').mkdir(); (root/'content').mkdir(); (root/'templates').mkdir(); (root/'public').mkdir()
(root/'.nift/config.json').write_text(json.dumps({'config':{
    'content-dir':'content/','content-ext':'.html','output-dir':'public/','output-ext':'.html',
    'default-template':'templates/template.html','build-threads':1,'incremental-mode':'modified','minify-exts':[]}}))
(root/'.nift/tracked.json').write_text(json.dumps({'tracked':[{'name':'/','title':'Home','template':'templates/template.html'}]}))
(root/'templates/template.html').write_text('<main>@content</main>\n')
(root/'content/index.html').write_text('<p>BASE</p>\n')
nift=os.environ['NIFT_BIN']
subprocess.run([nift,'build','--all'],cwd=root,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
# Force the first pass inside this long-running process to write public/. The
# regression only appears after that process has already scanned the parent.
(root/'content/index.html').write_text('<p>FIRST-PASS</p>\n')

proc=subprocess.Popen([nift,'build','--auto'],cwd=root,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
try:
    output=root/'public/index.html'; deadline=time.monotonic()+8
    while time.monotonic()<deadline and proc.poll() is None:
        if output.exists() and 'FIRST-PASS' in output.read_text(): break
        time.sleep(.05)
    else:
        if proc.poll() is not None: raise SystemExit('build --auto exited before initial write pass')
        raise SystemExit('build --auto did not complete initial write pass')

    stale=root/'public/mid-session.html.nift-tmp-99999999-101'
    stale.write_text('stale\n')
    time.sleep(.35)
    if not stale.exists(): raise SystemExit('idle build --auto removed stale temp without relevant filesystem activity')

    (root/'content/index.html').write_text('<p>CHANGED</p>\n')
    deadline=time.monotonic()+8
    while time.monotonic()<deadline and proc.poll() is None:
        output=root/'public/index.html'
        if output.exists() and 'CHANGED' in output.read_text() and not stale.exists(): break
        time.sleep(.05)
    else:
        if proc.poll() is not None: raise SystemExit('build --auto exited during recovery pass')
        raise SystemExit('mid-session stale temp was not recovered by subsequent relevant build activity')

    # A live-owner temp must remain protected during a later recovery epoch.
    live=root/'public/live.html.nift-tmp-{}-102'.format(os.getpid())
    live.write_text('live\n')
    (root/'content/index.html').write_text('<p>CHANGED-AGAIN</p>\n')
    deadline=time.monotonic()+8
    while time.monotonic()<deadline and proc.poll() is None:
        output=root/'public/index.html'
        if output.exists() and 'CHANGED-AGAIN' in output.read_text(): break
        time.sleep(.05)
    if not live.exists(): raise SystemExit('recovery removed a live-owner concurrent temp')
finally:
    if proc.poll() is None:
        proc.terminate()
        try: proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill(); proc.wait(timeout=5)
PY

echo "Filesystem recovery long-running contract passed"
