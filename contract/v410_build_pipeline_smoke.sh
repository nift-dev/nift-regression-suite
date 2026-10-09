#!/usr/bin/env bash
# Independent consumer contract: no first-party test sources are imported.
set -euo pipefail
export NIFT_BIN=${NIFT_BIN:?}
python3 - <<'PYTEST'
import json,os,pathlib,subprocess,tempfile
binary=os.environ['NIFT_BIN']
with tempfile.TemporaryDirectory(prefix='nrs-v410-pipeline-') as tmp:
 p=pathlib.Path(tmp)
 for d in ['.nift','content','public']:(p/d).mkdir()
 (p/'.nift/config.json').write_text(json.dumps({'config':{'content-dir':'content/','content-ext':'.html','output-dir':'public/','output-ext':'.html','default-template':'','minify-exts':[],'build-threads':2}}))
 entries=[{'name':'producer','title':'Producer','build':'produce.f'},{'name':'consumer','title':'Consumer','depends':['producer']}]
 def track():(p/'.nift/tracked.json').write_text(json.dumps({'tracked':entries}))
 def run(*args,ok=True):
  r=subprocess.run([binary,*args],cwd=p,capture_output=True,text=True,timeout=30)
  assert (r.returncode==0)==ok,(args,r.stdout,r.stderr)
  return r.stdout+r.stderr
 track();(p/'content/producer.html').write_text('placeholder');(p/'content/consumer.html').write_text('@input("public/producer.html")')
 (p/'produce.f').write_text('f := file(getenv("NIFT_HOOK_OUTPUT"))\nf.open("w")\nf.write("generated")\nf.save()\nf.close()\n')
 run('build','consumer');assert (p/'public/consumer.html').read_text()=='generated'
 before=(p/'.nift/public/consumer.info.json').stat().st_mtime_ns;run('build');assert (p/'.nift/public/consumer.info.json').stat().st_mtime_ns==before
 (p/'produce.f').write_text((p/'produce.f').read_text().replace('generated','updated'));run('build');assert (p/'public/consumer.html').read_text()=='updated'
 snapshot={str(f.relative_to(p)):f.read_bytes() for f in p.rglob('*') if f.is_file()}
 for mode in ['--rewrite','--redesign','--rewrite','--redesign']:run('init',mode)
 for name,data in snapshot.items():assert (p/name).read_bytes()==data,name
 entries[0]['depends']=['consumer'];track();out=run('status',ok=False);assert 'producer -> consumer -> producer' in out
 print('PASS v4.10 build pipeline / same-pass generated dependency / additive init / cycle validation')
PYTEST
