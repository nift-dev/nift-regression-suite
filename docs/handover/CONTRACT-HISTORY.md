# Contract history and institutional context

> This is a living historical companion to the repository's operational handover. The live repository remains authoritative. Maintain, correct, reorganize, or supersede this material as project evidence evolves while retaining durable rationale.

# Nift Regression Suite

## Project Context, Testing Philosophy, Development and Production-Readiness Handover

# 1. Identity

The standalone Nift regression suite is not merely a convenient collection of tests.

It is intended to act as an **implementation-independent behavioral contract** for Nift.

Conceptually:

```text
arbitrary Nift executable
        ↓
real CLI operations
        ↓
observable filesystem/output/status behavior
        ↓
PASS / FAIL
```

This independence is one of its most valuable properties.

---

# 2. Why it matters

The suite became central during Nift's architectural simplification.

It allowed us to remove/rewrite large amounts of implementation while asking:

> Did the external behavior we actually care about survive?

That makes it architectural infrastructure, not cleanup tooling.

---

# 3. Independence from implementation

Prefer black-box behavior.

Do not make the standalone suite depend on:

```text
Parser internals
C++ class names
private headers
internal data structures
```

unless there is an extraordinary reason.

A future Nift implementation in another language should theoretically be testable against much of the same suite.

---

# 4. Historical growth

The suite expanded through multiple checkpoints, historically reaching milestones around:

```text
146
211
245+
492+
```

checks/assertions/tests depending on stage and counting method.

Do not preserve those numbers as current documentation unless verified.

The important history is that coverage became progressively more adversarial.

---

# 5. Major bug families discovered

Historical regression work exposed or hardened areas including:

```text
backtick quote ambiguity
function-name lexical boundaries
CSS @media coexistence
unknown @ syntax
watch initialization
malformed watch JSON
empty tracked state
JSON escaping
JSON structural validation
CLI exit status
build-updated status propagation
missing generated outputs
directory dependencies
hash-cache refresh
path traversal
tracked/content/output collisions
sub-second mtimes
32-bit hash collision
dependency sidecar lifecycle
lexical JSON scope
control-flow interactions
```

These should inform future testing.

---

# 6. Deterministic rapid-edit testing

One particularly useful lesson came from same-second modification testing.

A timing-based test could flake.

The better test explicitly set timestamps such that:

```text
page-info mtime = second + .100...
dependency mtime = same second + .200...
```

This reliably tested sub-second behavior without hoping the filesystem scheduler cooperated.

General rule:

> Prefer controlled state over sleeps.

---

# 7. 32-bit collision testing

We deliberately constructed a hash collision rather than assuming collisions were merely theoretical.

That led to 64-bit hashing.

This is representative of the suite's intended adversarial character.

---

# 8. Test assumptions, not just features

When reviewing implementation, ask:

```text
What does this code assume can never happen?
```

Then attack it.

Examples:

```text
collection always non-empty
JSON value always string
path always stays inside project
hash never collides
mtime always distinguishes writes
dependency never changes identity
output always exists
function name always followed by whitespace
```

This methodology produced some of the highest-value Nift bugs.

---

# 9. Regression workflow

Preferred bug process:

```text
reproduce
↓
reduce
↓
make deterministic
↓
write failing black-box regression
↓
verify failure against old candidate
↓
fix implementation
↓
focused pass
↓
attack neighboring cases
↓
full suite
```

---

# 10. Test families, not isolated symptoms

If one malformed persistent JSON file crashes:

```text
watched.json
```

inspect siblings:

```text
exts.json
tracked.json
deps sidecars
configuration
```

If one path traversal exists in:

```text
track
```

inspect:

```text
cp
mv
rm
other filesystem commands
```

This is a core methodology.

---

# 11. Failure diagnostics

A large suite needs useful failure localization.

Historically test numbering and failure-focused output improved usability.

Preserve that.

A test suite that technically detects failures but makes them painful to diagnose damages development velocity.

---

# 12. Isolation

Tests should establish their own state.

Avoid:

```text
test 81 only works because test 80 created X
```

unless a deliberate lifecycle sequence is being tested.

Small temporary Nift projects are cheap.

Use them.

---

# 13. Current `$[...]` parameter-interpolation work

This should become a substantial new contract family.

Likely cases include:

```text
whole parameter:
    @input($[partial])

prefix:
    @input('partials/$[layout]')

suffix:
    @input('$[name].html')

multiple:
    @input('$[dir]/$[file]')

built-in metadata
JSON string values
loop-local values
nested lexical scope
shadowing
```

Failure/boundary cases:

```text
missing value
non-string JSON value
null
array
object
number
boolean
malformed $[
escaped syntax
quotes
parentheses
commas
$ signs in resolved values
@ signs in resolved values
empty strings
```

---

# 14. Directive integration

Test all directives whose parameter contract permits textual value interpolation.

Likely candidates requiring repository verification:

```text
@input
@dep
@path
@json path
```

and any others sharing the same parameter path.

Do not assume uniformity merely because they all use parentheses.

---

# 15. Non-recursive expansion

A particularly important language boundary:

If:

```text
$[x]
```

resolves to:

```text
$[y]
```

that result should normally remain data rather than triggering another evaluation pass, unless the settled implementation explicitly says otherwise.

Likewise a resolved value containing:

```text
@input(...)
```

must not suddenly become executable Nift syntax.

Test this explicitly.

---

# 16. Dynamic dependency lifecycle

This is probably the highest-risk interaction.

Example:

```text
selector = a.html
@input($[selector])
```

then selector changes to:

```text
b.html
```

The graph must evolve correctly.

Test transitions such as:

```text
A → B
B → A
A → missing
missing → A
A deleted after switching to B
B modified
selector source modified
```

as appropriate.

Dependency sidecars deserve direct attention.

---

# 17. Loops and lexical scope

Because loops and `@json` already exist, parameter interpolation must be tested inside lexical contexts.

For example conceptually:

```text
@for(item in data.items) {
    @input('partials/$[item.partial]')
}
```

Then test:

```text
nested loops
shadowing
outer variable
inner variable
scope exit
```

according to current semantics.

---

# 18. Internal versus external tests

Use both layers.

Internal C++ tests can efficiently test:

```text
parameter resolver
value lookup
scope handling
parser helper
dependency registration
```

The standalone suite tests:

```text
what the user actually experiences
```

Neither replaces the other.

---

# 19. Role in Nift production status

The regression suite is one of the principal gates for calling Nift production-ready.

The objective is **not**:

```text
reach arbitrary test count
```

It is:

```text
major public behavior protected
known historical bug families protected
new language features protected
filesystem mutations protected
incremental behavior protected
watch behavior protected
dependency/requirement behavior protected
error paths controlled
adversarial interactions exercised
```

---

# 20. Nift production-readiness goal

The current high-level goal for Nift is:

> Reach a point where the stripped/current architecture has sufficient cumulative correctness evidence, real-world dogfooding, documentation accuracy, performance stability, and release-process confidence that it can reasonably be presented as production-ready rather than merely an impressive development build.

Historically, Nift is the closest of the three products to this state.

---

# 21. Current Nift production roadmap from the suite perspective

**CURRENT — MUST BE REVISED CONTINUOUSLY**

The present direction is approximately:

```text
finish current intended language semantics
    including $[...] parameter interpolation
↓
encode those semantics in independent regression suite
↓
run existing full suite
↓
perform targeted interaction/adversarial audit
↓
run sanitizer/native validation
↓
validate incremental/watch/dependency behavior
↓
validate candidate against Nift website
↓
recheck performance
↓
resolve release-blocking defects
↓
documentation/release reconciliation
↓
production release decision
```

This is not a frozen checklist.

If parameter interpolation exposes a deeper dependency-model weakness, for example, the roadmap must expand accordingly.

---

# 22. Production does not end testing

After production status:

```text
every bug gets regression where appropriate
new features expand contract
new bug families trigger adversarial audits
new platforms expand validation
performance regressions remain monitored
```

Production means confidence in the development/release process, not that testing is finished.

---

# 23. Roadmap maintenance rule

Put this in durable suite documentation:

> The production-readiness and ongoing quality roadmap is a living artifact. At each significant development checkpoint, review new failures, new coverage, unresolved risks, architecture changes, platform evidence and real-world behavior. Reorder, expand, reduce or replace roadmap items based on evidence. A historical roadmap must never override newly discovered project reality.

---

# 24. Canonical ownership

Codex should determine the relationship between:

```text
Nift-local tests
standalone regression suite
```

and document where new black-box regressions originate.

Do not allow silent divergence.

---

# 25. Definition of success

A strong suite is one where future Codex can make a deep Nift refactor and receive a credible answer to:

> Did I preserve Nift?

That is the long-term objective.

---

---

