#!/usr/bin/env bash
set -euo pipefail
NIFT=${NIFT_BIN:?}; R=$(mktemp -d); trap 'rm -rf "$R"' EXIT; cd "$R"; "$NIFT" init >/dev/null
B(){ tr -d '[:space:]' < public/index.html; }

# --- Signed 64-bit integers: exact boundaries, deterministic overflow. ---
cat > content/index.html <<'EOT'
$[hi := 9223372036854775807]$[lo := -9223372036854775808]
$[hi],$[lo]
$[s := 9223372036854775806]$[s + 1]
$[m := 9007199254740993]$[m + 1]
EOT
"$NIFT" build --all >/dev/null
o=$(B); [[ "$o" == *"9223372036854775807"* ]] && [[ "$o" == *"-9223372036854775808"* ]] && [[ "$o" == *"9223372036854775807"* ]] && [[ "$o" == *"9007199254740994"* ]]

cat > content/index.html <<'EOT'
$[x := 9223372036854775807]$[x + 1]
EOT
if "$NIFT" build --all >/dev/null 2>&1; then echo "int64 overflow unexpectedly succeeded" >&2; exit 1; fi

# Mixed numeric comparison: int64 vs double equality/order.
cat > content/index.html <<'EOT'
$[1 == 1.0],$[1 < 1.5],$[9007199254740993 > 9007199254740992.0]
EOT
"$NIFT" build --all >/dev/null
o=$(B); [[ "$o" == *"true,true,true"* ]]

# --- Compound assignment and ++/--. ---
cat > content/index.html <<'EOT'
$[i := 5]$[i += 3]$[i -= 1]$[i *= 2]$[i /= 2]$[i]
$[j := 5]$[a := ++j]$[b := j--]$[a],$[b],$[j]
$[s := "ab"]$[s += "cd"]$[s]
EOT
"$NIFT" build --all >/dev/null
o=$(B); [[ "$o" == *"8"* ]] && [[ "$o" == *"6,6,5"* ]] && [[ "$o" == *"abcd"* ]]

# Fractional modulo remains rejected (v4.2 contract).
cat > content/index.html <<'EOT'
$[1.5 % 1]
EOT
if "$NIFT" build --all >/dev/null 2>&1; then echo "fractional modulo unexpectedly succeeded" >&2; exit 1; fi

# --- Mutable arrays: mutation, access helpers, structural equality, identity. ---
cat > content/index.html <<'EOT'
$[a := [1,2,3]]$[a.push(4)]$[a.insert(1,9)]$[a.remove(1)]$[a.pop()]
$[a.size()],$[a.first()],$[a.last()],$[a.indexOf(3)],$[a.contains(9)]
$[b := a]$[c := copy(a)]$[d := deepcopy(a)]
$[same(a,b)],$[same(a,c)],$[a == c]
$[e := [1,[2,3]]]$[f := [1,[2,3]]]$[e == f]
EOT
"$NIFT" build --all >/dev/null
o=$(B); [[ "$o" == *"3,1,3,2,false"* ]] && [[ "$o" == *"true,false,true"* ]] && [[ "$o" == *"true"* ]]

cat > content/index.html <<'EOT'
$[a := []]$[a.pop()]
EOT
if "$NIFT" build --all >/dev/null 2>&1; then echo "pop on empty array unexpectedly succeeded" >&2; exit 1; fi

# --- stack / queue / prique ordering. ---
cat > content/index.html <<'EOT'
$[s := stack()]$[s.push(1)]$[s.push(2)]$[s.push(3)]
$[q := queue()]$[q.push(1)]$[q.push(2)]$[q.push(3)]
$[p := prique()]$[p.push(3)]$[p.push(1)]$[p.push(2)]
@for(x : s){$[x]}|@for(x : q){$[x]}|@for(x : p){$[x]}
EOT
"$NIFT" build --all >/dev/null
o=$(B); [[ "$o" == *"321|123|123"* ]]

# --- map / sorted_map / set / sorted_set ordering and logical equality. ---
cat > content/index.html <<'EOT'
$[m := map()]$[m.set("b",2)]$[m.set("a",1)]$[m.set("b",3)]
@for((k,v) : m){$[k]=$[v]}|$[m.size()]|$[m.get("a")]|
$[sm := sorted_map()]$[sm.set("b",2)]$[sm.set("a",1)]@for((k,v) : sm){$[k]}|
$[st := set()]$[st.add(2)]$[st.add(1)]$[st.add(1)]@for(x : st){$[x]}|$[st.size()]|
$[ss := sorted_set()]$[ss.add(3)]$[ss.add(1)]$[ss.add(2)]@for(x : ss){$[x]}|$[ss.size()]|
$[m1 := map()]$[m1.set("a",1)]$[m1.set("b",2)]
$[m2 := map()]$[m2.set("b",2)]$[m2.set("a",1)]
$[m1 == m2]|$[s1 := set()]$[s1.add(1)]$[s1.add(2)]$[s2 := set()]$[s2.add(2)]$[s2.add(1)]$[s1 == s2]|
$[g := map()]$[g.set(1,"x")]$[g.contains(1.0)]|$[g.get(1.0)]|
EOT
"$NIFT" build --all >/dev/null
o=$(B)
[[ "$o" == *"b=3a=1|2|1|"* ]]   # map: update retains position (b first); size 2; get("a")=1
[[ "$o" == *"ab|"* ]]           # sorted_map iterates by key
[[ "$o" == *"21|2|"* ]]         # set: insertion order 2,1; duplicate add skipped; size 2
[[ "$o" == *"123|3|"* ]]        # sorted_set iterates by value
[[ "$o" == *"true|true|"* ]]    # map + set logical equality ignore insertion history
[[ "$o" == *"true|x"* ]]        # int/float key equivalence (1 == 1.0)

# --- same() identity. ---
cat > content/index.html <<'EOT'
@struct(p){ x := 0 }
$[p0 := p()]$[q0 := p()]$[same(p0,p0)],$[same(p0,q0)],$[same(p0,copy(p0))]
EOT
"$NIFT" build --all >/dev/null
o=$(B); [[ "$o" == *"true,false,false"* ]]

# --- First-class callables and lambdas. ---
cat > content/index.html <<'EOT'
@fn(twice(x)){ return x * 2 }
$[f := twice]$[f(21)]
$[e := x => x * 3]$[e(4)]
$[bl := x => { if(x < 0) { return -x }; return x }]$[bl(-5)],$[bl(5)]
EOT
"$NIFT" build --all >/dev/null
o=$(B); [[ "$o" == *"42"* ]] && [[ "$o" == *"12"* ]] && [[ "$o" == *"5,5"* ]]

# --- Closures: binding-not-snapshot capture, mutable capture, escaping, sharing. ---
cat > content/index.html <<'EOT'
$[fac := 10]$[mul := x => x * fac]$[fac = 20]$[mul(2)]
$[n := 0]$[a := () => ++n]$[b := () => ++n]$[a()],$[b()],$[a()],$[n]
@fn(counter(start)) {
    n := start
    return () => n++
}
$[c1 := counter(10)]$[c2 := counter(100)]$[c1()],$[c1()],$[c2()],$[c2()]
EOT
"$NIFT" build --all >/dev/null
o=$(B); [[ "$o" == *"40"* ]] && [[ "$o" == *"1,2,3,3"* ]] && [[ "$o" == *"10,11,100,101"* ]]

# --- Higher-order operations. ---
cat > content/index.html <<'EOT'
$[a := [1,2,3,4]]
@for(x : a.map(x => x * 2)){$[x]}|@for(x : a.filter(x => x % 2 == 0)){$[x]}|
$[a.reduce((acc,x) => acc + x, 0)],$[a.any(x => x == 4)],$[a.all(x => x > 0)],$[a.find(x => x > 2)],$[a.count(x => x % 2 == 0)]
$[u := [3,1,2]]$[u.sort()]@for(x : u){$[x]}|$[v := [3,1,2]]$[v.sort((x,y) => x > y)]@for(x : v){$[x]}|
$[m := map()]$[m.set("a",1)]$[m.set("b",2)]@for(x : m.map((k,v) => v * 10)){$[x]}|
EOT
"$NIFT" build --all >/dev/null
o=$(B)
[[ "$o" == *"2468|24|"* ]]
[[ "$o" == *"10,true,true,3,2"* ]]
[[ "$o" == *"123|321|"* ]]
[[ "$o" == *"1020|"* ]]

# Empty-collection higher-order and reduce-with-initial-accumulator.
cat > content/index.html <<'EOT'
$[e := []]$[e.reduce((acc,x) => acc + x, 5)],$[e.any(x => x)],$[e.all(x => x)],$[e.find(x => x)],$[e.count(x => x)]
EOT
"$NIFT" build --all >/dev/null
o=$(B); [[ "$o" == *"5,false,true,null,0"* ]]

# Callback errors and empty/const mutation rejections must fail the build.
cat > content/index.html <<'EOT'
$[a := [1,2,3]]$[a.map(x => 1 / 0)]
EOT
if "$NIFT" build --all >/dev/null 2>&1; then echo "callback error unexpectedly swallowed" >&2; exit 1; fi
cat > content/index.html <<'EOT'
$[const a := [1]]$[a.push(2)]
EOT
if "$NIFT" build --all >/dev/null 2>&1; then echo "const array mutation unexpectedly succeeded" >&2; exit 1; fi

# deepcopy clones collections (identity must differ).
cat > content/index.html <<'EOT'
$[s := set()]$[s.add(1)]$[d := deepcopy(s)]$[d.add(2)]$[s.size()],$[d.size()],$[same(s,d)]
EOT
"$NIFT" build --all >/dev/null
o=$(B); [[ "$o" == *"1,2,false"* ]]

# Rendering a callable/collection value must fail rather than leak.
cat > content/index.html <<'EOT'
$[m := map()]$[m.set("a",1)]$[m]
EOT
if "$NIFT" build --all >/dev/null 2>&1; then echo "collection reference rendered instead of failing" >&2; exit 1; fi

# A lambda whose body fails must be a build error, not silent passthrough.
cat > content/index.html <<'EOT'
$[f := () => missing_name]$[f()]
EOT
if "$NIFT" build --all >/dev/null 2>&1; then echo "lambda body error silently passed through" >&2; exit 1; fi
# --- Mixed int64/double ordering across the full range (frozen numeric contract). ---
cat > content/index.html <<'EOT'
$[9223372036854775807 < 1e19],$[9223372036854775807 < 9223372036854775808.0],$[-9223372036854775808 > -1e19]
EOT
"$NIFT" build --all >/dev/null
o=$(B); [[ "$o" == *"true,true,true"* ]]
cat > content/index.html <<'EOT'
$[9007199254740992 == 9007199254740992.0],$[9007199254740993 == 9007199254740992.0],$[9007199254740993 > 9007199254740992.0]
EOT
"$NIFT" build --all >/dev/null
o=$(B); [[ "$o" == *"true,false,true"* ]]
# Equality and ordering agree.
cat > content/index.html <<'EOT'
$[x := 9007199254740992]$[y := 9007199254740992.0]$[x==y],$[x<y],$[x>y]
EOT
"$NIFT" build --all >/dev/null
o=$(B); [[ "$o" == *"true,false,false"* ]]

# --- Forbidden user-visible cycles are rejected deterministically. ---
cat > content/index.html <<'EOT'
@struct(other){x:=0}@struct(node){next:=other()}
$[a := node()]$[a.next = a]
EOT
if "$NIFT" build --all >/dev/null 2>&1; then echo "self cycle unexpectedly allowed" >&2; exit 1; fi
cat > content/index.html <<'EOT'
@struct(other){x:=0}@struct(node){next:=other()}
$[a := node()]$[b := node()]$[a.next = b]$[b.next = a]
EOT
if "$NIFT" build --all >/dev/null 2>&1; then echo "indirect cycle unexpectedly allowed" >&2; exit 1; fi
# Acyclic sharing and aliases remain legal.
cat > content/index.html <<'EOT'
@struct(other){x:=0}@struct(node){next:=other()}
$[a := node()]$[b := node()]$[c := node()]$[a.next = b]$[b.next = c]$[a.next.next == c]
$[d := a]$[d == a]
EOT
"$NIFT" build --all >/dev/null
o=$(B); [[ "$o" == *"true"* ]] && [[ "$o" == *"true"* ]]
# A lambda stored in a collection is not a forbidden user cycle (callables are leaves).
cat > content/index.html <<'EOT'
$[xs := []]$[xs.push(() => 7)]$[f := xs[0]]$[f()]
EOT
"$NIFT" build --all >/dev/null
o=$(B); [[ "$o" == *"7"* ]]

# Numeric/bool map keys are iterable via the object @for tuple form.
cat > content/index.html <<'EOT'
$[m := map()]$[m.set(1,"one")]$[m.set(2,"two")]@for((k,v) : m){$[k]=$[v]}|$[m.get(1)]
$[b := map()]$[b.set(true,"yes")]@for((k,v) : b){$[k]=$[v]}|
EOT
"$NIFT" build --all >/dev/null
o=$(B); [[ "$o" == *"1=one2=two|one"* ]] && [[ "$o" == *"true=yes|"* ]]

# Map @for must preserve typed keys: int/string and bool/string collisions are
# distinct entries, and the iterated key round-trips through typed lookup.
cat > content/index.html <<'EOT'
$[m := map()]$[m.set(1,"int")]$[m.set("1","string")]@for((k,v) : m){$[k]=$[v]}|$[m.size()]
$[m2 := map()]$[m2.set(true,"bool")]$[m2.set("true","string")]@for((k,v) : m2){$[k]=$[v]}|$[m2.size()]
$[m3 := map()]$[m3.set(1,"int")]$[m3.set("1","string")]@for((k,v) : m3){$[m3.get(k)]}|
EOT
"$NIFT" build --all >/dev/null
o=$(B); [[ "$o" == *"1=int1=string|2"* ]] && [[ "$o" == *"true=booltrue=string|2"* ]] && [[ "$o" == *"intstring"* ]]
# 1 and 1.0 remain one logical numeric key; insertion/sorted order preserved.
cat > content/index.html <<'EOT'
$[m := map()]$[m.set(1,"a")]$[m.set(1.0,"b")]$[m.size()],$[m.get(1)],$[m.get(1.0)]
$[im := map()]$[im.set(2,"two")]$[im.set(1,"one")]@for((k,v) : im){$[k]}|$[sm := sorted_map()]$[sm.set("b",2)]$[sm.set("a",1)]@for((k,v) : sm){$[k]}|
EOT
"$NIFT" build --all >/dev/null
o=$(B); [[ "$o" == *"1,b,b"* ]] && [[ "$o" == *"21|ab|"* ]]
