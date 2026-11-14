# AGENTS.md - ai-decisions

## TL;DR

Read [`SKILL.md`](./SKILL.md) first — the payload contract, question schema and output shape live there.

## Non-Negotiables

- **The shared core is single-sourced; never edit a skill's copy.** The request, validation, retry and
  audit code lives at `.agents/_smooth-devex-shared/decisions/decisions_core.py`. The installer copies it
  into `<skill>/decisions/lib/` for every consumer listed in `DECISIONS_CORE_CONSUMERS`
  (`scripts/install-skills.{sh,ps1}`), and `ai-ralph-loop` consumes the same file. A fix made to a copied
  `decisions/lib/decisions_core.py` is overwritten on the next install and silently diverges from
  ralph-loop's behaviour.
- **`decide.sh` resolves the core from two paths on purpose.** `../decisions/lib/` is the installed
  layout; `../../../_smooth-devex-shared/decisions/` is the in-repo layout the test suites run against.
  Removing either breaks one of the two; a missing core exits 1 because an install that shipped no core
  is broken, not a fallback case.
- **Probability keys are derived from the outgoing criteria.** A `choice` criteria object or a `score`
  criteria array is what `validate_answer` checks against; changing a criteria shape without changing the
  response contract makes every answer invalid and turns the caller into a permanent fallback.
- **`noul` stays out of v1.** `validate_questions` refuses every type but `choice`/`score`. Adding one
  without a validation rule and a documented answer shape ships a contract that cannot be validated.
- **Env vars are read by `decide.sh` and its embedded Python; the key never leaves the environment.**
  `SMOOTH_DEVEX_DECISIONS_{ENABLED,BASE_URL,PATH,MODEL,MAX_ATTEMPTS,TIMEOUT}` are read in the bash wrapper,
  `SMOOTH_DEVEX_DECISIONS_API_KEY` only inside the Python process via `os.environ` where it becomes the
  `Authorization` header — never argv, URL, audit document or committed text
  ([skill-secret-handling](../../../.github/instructions/skills/skill-secret-handling.instructions.md)).
- **The shared core sits outside the SkillSpector scan root.** `.github/workflows/skill-scan.yml`
  triggers on and scans `.agents/skills/**` only, so a change to
  `.agents/_smooth-devex-shared/decisions/` is neither scanned nor gated. Review it by hand against the
  trigger classes in `skillspector-pre-pr`, or extend the workflow deliberately — never assume the gate
  covered it.
- **`tests/` is repo-only and the core is not a skill source file.** The installer prunes `tests/`; the
  shipped payload is `SKILL.md`, `AGENTS.md`, `README.md`, `agents/openai.yaml`, `scripts/decide.sh`.
  Adding the core to the skill's source tree would ship a second, drifting copy.

## Test References

- L0 core: `python3 -B .agents/_smooth-devex-shared/decisions/tests/test_decisions_core.py -v`
- L1 entrypoint (loopback stub): `python3 -B .agents/skills/ai-decisions/tests/test_decide.py -v`
- Regression (ralph-loop consumer): `python3 -B .agents/skills/ai-ralph-loop/decisions/tests/test_decision_evaluate.py -v`
- Installer fan-out: `bash scripts/test-install-skills.sh`

## Changelog

| Date | Change | Ref |
| :---- | :---- | :---- |
| 2026-11-14 | Initial: shared-core ownership, dual core paths, criteria-derived keys, `noul` exclusion, env-only key | #170 |
