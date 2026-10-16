---
name: ai-ralph-loop
description: 'Ralph loop over the current change: review, fix and verify, repeated with fresh eyes until a full pass finds nothing or the loop cap (default 10) is hit. Checks feature gaps, potential bugs, architectural issues, YAGNI, KISS and clean code consistency, including L0/L1/L2 test coverage, placement and quality. Findings are grounded in known Understandings, *AGENTS.md, rules and specs; the run ends with a fix table and test verification status. Trigger on "/ai-ralph-loop", "ralph loop", "loop until no findings", "review and fix until clean". Not a one-shot review (use /code-review); never commits.'
effort: high  # multi-loop review, triage and fix judgment
---

# Ralph Loop — Skill

The same review-and-fix prompt, run again and again over one scope, each pass with fresh eyes, until a
full pass finds nothing. Progress lives in a ledger on disk, not in the conversation — that is what lets
every pass start clean and what stops a pass re-raising what an earlier one already settled.

## TL;DR

1. Bare `/ai-ralph-loop` runs the full loop: branch diff vs `origin/main`, up to 10 loops, stop at the first clean full-scope pass.
2. Six categories count — see [Categories](#categories). [Test focus](#test-focus) is mandatory within them: check L0/L1/L2 coverage, placement and quality, not just production code.
3. A finding without evidence is rejected. The [Evidence bar](#evidence-bar) is what makes the loop converge instead of running to the cap.
4. Every loop: review → triage → fix → verify → record. Loop 1 reviews the full scope; later loops review only what the last loop changed, then one full sweep confirms.
5. Ends with the [fix table](#output). Never commits or pushes.

## Switches

No switch is needed — a bare invocation is the full run.

| Switch | Effect | Default |
|--------|--------|---------|
| _(none)_ | Full run over the branch diff, up to 10 loops | — |
| `--loops <n>` | Loop cap; any positive integer | `10` |
| `--scope <path\|glob>` | Review these files instead of the branch diff | branch diff vs `origin/main` |
| `--spawn` | Run the two review lenses as parallel subagents with fresh context | off — both lenses run sequentially, inline, in the current agent pid |
| `--notests` | Do not create new tests during the loop; retain coverage review, existing-test repairs and verification | off — create required tests |

Single-dash spellings (`-loops 5`) are accepted. An unrecognised switch or a non-positive `--loops` is
not guessed at: say what was passed and ask.

### `--notests` — no new tests

With `--notests`, do not create new test files or test cases at any tier, including new parameterised
cases in existing files and regression tests for production fixes. This restriction applies to every
loop and reviewer mode and composes with `--scope`, `--loops` and `--spawn`.

Continue reviewing test existence, coverage, placement and quality, and run existing relevant suites.
Repairs to existing tests remain allowed within scope; never weaken assertions, delete tests or skip
them to hide a failure. A coverage gap needing a new test is `deferred` with reason `--notests`, the
missing scenario and required tier; do not mark it satisfied or re-raise it on later loops. Production
fixes may proceed without creating a regression test, but record the missing regression coverage as a
separate deferred finding. Report deferred gaps and test incompleteness in the final output.

Without `--notests`, required test creation remains part of the normal loop.

## Categories

| Category | Qualifies when | Not a finding |
|----------|----------------|---------------|
| Feature gap | A requirement **cited from a source** — worktask acceptance criterion, HLD, `*AGENTS.md` Requirements, Understanding, PR or issue body — is missing or only partly built; includes missing meaningful test coverage required by [Test focus](#test-focus) | A feature nobody asked for, or arbitrary test quotas beyond Test focus (that is YAGNI) |
| Potential bug | A concrete input or state produces a wrong result, crash, data loss, race or leak | "Might fail" with no path to the failure |
| Architectural issue | Breaks a layer boundary, a tier boundary in Test focus, an ADR/LADR, or a rule (e.g. `backend/architecture-slices`) | Preferring another pattern |
| YAGNI | Code, abstraction, option or parameter with no current caller and no cited requirement | An extension point an ADR mandates |
| KISS | The same behaviour fits in clearly less code or indirection, with nothing lost | A rewrite to taste |
| Clean code consistency | Diverges from a rule (`clean-code`, `collection-types`, logging conventions, …), the test-quality constraints in Test focus, or the idiom the surrounding code already uses | Formatting — `.editorconfig` owns it |

## Evidence bar

A finding carries all four, or it is rejected:

- **Category** — one of the six above.
- **Location** — `file:line`.
- **Evidence** — the failure scenario (input → wrong outcome), or the path of the rule, ADR, `*AGENTS.md`, Understanding or spec it breaks.
- **Fix** — one sentence.

On conflict between sources: rule > ADR/LADR > nearest `*AGENTS.md` > newest Understanding. The running
system (code plus passing tests) outranks an Understanding — a disagreement between them is reported,
never "fixed" by bending code toward the Understanding. Feature gap vs YAGNI: a cited requirement wins;
without a citation, YAGNI wins.

## Test focus

Check test **existence, placement and quality** on every bare Ralph run, within the affected feature
scope. On full-scope passes, inspect all affected features; on delta passes, revisit features affected
by the delta. Existing tests count when they exercise current behaviour; do not create duplicates to
satisfy a count. Documentation-only changes do not require feature tests.

### Required coverage

| Tier | Required focus | Evidence of sufficient coverage |
|------|----------------|---------------------------------|
| L2 — integration | At least one happy-path test per affected feature | Enter through the public application boundary and exercise the full application stack, including real persistence where applicable. Assert the successful business outcome and relevant persisted state or externally visible side effects. A mocked handler or component-only test does not satisfy L2. |
| L1 — component | Unhappy paths through the responsible component or layer | Cover applicable validation failures, rejected business operations, missing/conflicting state, and dependency failures. Assert the error contract and relevant side effects, including absence of unintended writes. Use real infrastructure or controlled boundary substitutes according to local test conventions. |
| L0 — unit | Exception contracts, mappings, low-level maths and deterministic result-oriented logic | Exercise these behaviours in isolation, without I/O. Check relevant boundaries, edge cases and exact outputs, including exception type and contract-relevant details. An exception produced by isolated logic belongs here; its translation into a component-level failure belongs in L1. Do not add trivial getter/setter tests or require a unit test for every class. |

Use the lowest tier that proves each behaviour; retain the mandatory L2 happy path. Add extra L2 cases
only when a specific risk requires full-stack proof. Do not duplicate an entire unhappy-path matrix
across tiers.

### Review and evidence

- Map each affected feature's requirements and changed behaviour to concrete test names and files at
  L0/L1/L2. Record missing coverage and justified non-applicable cases; L0/L1 need applicable behaviours,
  not arbitrary test quotas. L2's minimum applies to every affected feature.
- Inspect test bodies, not filenames or coverage percentages alone. Tests must exercise production
  behaviour, assert observable outcomes that distinguish correct from incorrect behaviour, use isolated
  state and deterministic data, and avoid order dependence, sleeps and uncontrolled external services.
  An empty, assertion-free, permanently skipped or vacuously passing test does not count.
- Raise gaps through the existing categories, not a seventh category: missing meaningful coverage is a
  Feature gap citing this section and the affected requirement; a demonstrated defect is a Potential bug;
  a broken tier boundary is an Architectural issue. Apply the Evidence bar. For an absent test, cite the
  production location and record the searched test projects/files and missing scenario.
- Fix accepted gaps with focused tests in the required tier, rather than copying the tier of existing
  tests blindly. With `--notests`, defer gaps that require a new test instead. Read related tests outside
  the diff for evidence; if changing them would exceed the permitted fix scope, defer with the exact
  missing test and reason.
- Run relevant L0, L1 and L2 suites for affected behaviour. Record commands, pass/fail/skip results and
  baseline failures. Missing infrastructure or an unrun suite is blocked/unverified, never a pass.
  Report unresolved coverage and verification blockers explicitly; review convergence alone is not a
  test-complete verdict.

## Workflow

### Step 0 — Context pack (once per run)

1. **Scope.** Default:

   ```bash
   base=$(git merge-base origin/main HEAD)
   { git diff --name-only --diff-filter=d "$base"; git ls-files --others --exclude-standard; } | sort -u
   ```

    With `--scope`, expand the path or glob instead. Drop binaries, lock files and generated code
    (EF migration designers, snapshots). Empty scope → stop and say so. In the default scope, related
    tests for affected features are also permitted fix targets, including new test files unless
    `--notests` is set. An explicit `--scope` remains the fix boundary; related tests outside it may be
    read for evidence, not edited.
2. **Known context**, loaded once and listed in the ledger so every reviewer reads the same pack:
   - `*AGENTS.md` chain for each scope file (`.agents/skills/context-load-agents-context/scripts/load-agents-context.sh --file <path>`, or walk ancestor directories).
   - Rules whose scope matches a scope file (index: `.agents/rules/AGENTS.md`).
   - `.context/understandings/INDEX.md` → every unit whose question matches the scope's subject. No store → continue without it.
   - Specs: active worktask under `.context/work-tasks/`, referenced `docs/hlds/`, PR body (`gh pr view --json body`) when a PR exists.
3. **Test inventory.** Apply Test focus: identify affected features and map requirements/scenarios to
   L0/L1/L2 test names and files, including tests outside the diff. Record searched locations for missing
   coverage and reasons for non-applicable cases. Load related tests' context chains and applicable
   rules into the context pack. For documentation-only scope, record that exemption.
4. **Baseline verify.** Build and run relevant L0/L1/L2 tests covering the scope (commands from root
   `AGENTS.md`). Record commands, failures and skips as baseline — a loop is judged on *new* failures
   only. Baseline failures do not waive coverage obligations; unavailable suites remain blocked/unverified.
5. **Open the ledger** (below).

### Ledger

`.context/ralph-loop/<yyyyMMdd-HHmm>/ledger.md` (UTC stamp, one folder per run). Header: scope list,
active switches (including `--notests`), context pack paths, baseline verify result. Keep the test
inventory current in a separate table:

```markdown
| Feature | Requirement/scenario | Tier | Test name and file / searched locations | Coverage/quality gap or N/A reason | Verify command and pass/fail/skip/blocked result |
```

Finding body:

```markdown
| ID | Loop | Category | File(s) | Status | Rationale |
```

`Status` is `fixed`, `rejected`, `deferred` or `oscillation`. Re-read the ledger at the start of every
loop — never rely on recall of earlier loops.

### Loop n (1 … cap)

1. **Review.** Target: loop 1 and any confirmation sweep = full scope; otherwise the **delta** — files
   edited in loop n−1 plus their direct callers and importers, and the affected feature tests. Review
   through both lenses, each with the [Reviewer brief](#reviewer-brief):
   - Lens A: feature gap, potential bug — include required test coverage and concrete defects exposed by tests.
   - Lens B: architectural issue, YAGNI, KISS, clean code consistency — include test tier boundaries, quality and unnecessary duplication.

   Without `--spawn` (the default), run the two lenses **sequentially, inline, in the current agent
   pid**: lens A first over the target files, then lens B, re-reading the target files from disk
   between them so neither lens inherits the other's framing. With `--spawn`, run them as two
   parallel subagents, each handed the reviewer brief, the target file list, and the ledger path.
   A harness that cannot spawn subagents ignores `--spawn` and runs inline — never fail the run
   for it.
2. **Triage.** Check each finding against the code yourself. Accept, reject or defer it with a reason.
   A finding matching a ledger row (same file, same issue) is dropped. With `--notests`, defer test
   creation findings rather than accepting them for a fix; keep production fixes eligible.
3. **Fix.** Accepted findings only, in order: potential bug → feature gap → architectural issue → the
   rest. Smallest change that resolves it, matching the surrounding code. A bug fix gets a regression
   test at the tier required by Test focus unless `--notests` is set; then fix the production issue and
   defer any missing regression coverage separately. Existing test placement is not authoritative.
   A fix that would leave the permitted scope is `deferred`.
4. **Verify.** Build touched projects and run relevant L0/L1/L2 suites for affected behaviour, including
   required feature tests in otherwise untouched test projects. Update the inventory with commands and
   pass/fail/skip/blocked results; unrun or blocked suites never count as passing. A new failure → fix
   forward, at most two attempts; still red → stop the run, report the failing command, leave the tree
   as it is.
5. **Record.** One ledger row per finding, then a summary line:
   `Loop n: target=<full|delta k files> accepted a / rejected r / deferred d`.
6. **Exit check.**
   - 0 accepted on a full-scope pass → review **converged**, stop; unresolved test gaps or verification blockers still prevent a test-complete verdict.
   - 0 accepted on a delta pass → the next loop is a full-scope confirmation sweep.
   - n = cap → stop and report what is still open.

**Guards.** A fix that would undo an earlier loop's fix is rejected as `oscillation` — the earlier fix
stands and both are named in the report. A finding whose fix failed verification twice is `deferred`.

### Reviewer brief

Hand this section, the Categories table, the Evidence bar and Test focus to each reviewer, with the
target file list, active switches and the ledger path. Include the `--notests` switch instructions when
set. This hand-off applies to both inline and spawned reviews.

- Read-only. Read the ledger first; never re-raise an item it lists.
- Read the context pack paths in the ledger header.
- Review target production and test files; inspect related tests outside the target list for Test focus
  evidence. Do not audit unrelated features. Anchor missing-test findings to the affected production location.
- Apply Test focus through your lens and consult the ledger's test inventory; do not treat existing
  test files or a green build as proof of adequate coverage or quality.
- `--notests` does not suppress coverage findings. Identify missing tests and required tiers so triage
  can defer their creation; do not treat the switch as evidence that coverage is sufficient.
- Report only your lens's categories, and only findings that meet the Evidence bar.
- Reply with table rows `| Category | file:line | Evidence | Fix |`, most severe first, or the single word `none`.
- No praise, no summary, no formatting nits.

### Finish

1. When a fix changed behaviour a `*AGENTS.md` describes, update that file and its changelog.
2. When a loop surfaced knowledge worth keeping, suggest `/ai-understanding --export`.
3. Never commit or push.

## Output

The final message is this table — `fixed` rows only, IDs from the ledger:

```markdown
| ID | Category | File(s) fixed | Rationale | Loop |
|----|----------|---------------|-----------|------|
| RL-001 | Potential bug | `src/Project.Application/Features/Orders/CreateOrderHandler.cs` | Null customer id reached the repository; guard + regression test | 1 |
```

Then three lines:

- **Result** — `converged at loop k` · `cap reached (n loops)` · `stopped: verify red at loop k`.
- **Verify** — build/test commands and state against baseline, L0/L1/L2 coverage and execution status,
  and any skips or infrastructure blockers. Say `test complete` only when required coverage and quality
  checks are satisfied and relevant suites passed; otherwise `test incomplete` with reasons. A
  documentation-only exemption is `not applicable`, not a fabricated test pass. With `--notests`, state
  `test creation disabled (--notests)`; this is not itself a coverage failure when existing tests suffice.
- **Not fixed** — rejected / deferred / oscillation counts, one line per deferred or oscillation item,
  unresolved test gaps (including scenario, tier and `--notests` reason for deferred test creation), and
  the ledger path.

No fixed rows → omit the fix table. Say `no findings` only when no findings remain and give the Result
and Verify lines; retain Not fixed whenever unresolved findings or test gaps remain.
