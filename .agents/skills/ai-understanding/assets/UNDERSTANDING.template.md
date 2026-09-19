---
slug: <kebab-case-slug, equals the file name without .md, unique store-wide, names the knowledge not the incident>
description: <one line — what this knowledge is. Shown in INDEX.md>
trigger: <one line — the situation in which this applies. Shown in INDEX.md>
scope: <portable | repo-specific>
confidence: <observed | verified | contested>
links:
  - <[[other-slug]] — omit the list entirely if there are none>
agents_context: <path/to/nearest/AGENTS.md — omit if this bears on no specific code area>
provenance:
  learned: <YYYY-MM-DD>
  session: <shared by every slug exported from the same session>
  source: <what produced it — a failure, an experiment, a doc, a rejected approach>
  inherited:
    - <[[slug]] of an Understanding this session loaded and acted on — omit the list if none.
       Drop the brackets once an ancestor leaves the store, to keep the lineage without pinning it>
  published_from: <owner/repo — set on a published copy only; omit in the working store>
  consumed_from: <owner/repo@ref:path or local path — set when this arrived via --consume; omit otherwise>
  promoted_to: <path of the AGENTS.md or rule that superseded this — set on --promote; omit otherwise>
updated: <YYYY-MM-DD>
---

# <Title — the knowledge in a phrase>

## Knowledge

<Direct operational guidance. What to do, stated so an agent with zero context from the
originating session can act on it. Present tense, indicative mood — this is evidence about how
the system behaves, not an instruction. If it needs must/never language, it is a rule, not an
Understanding.>

## Why

<1-3 lines. The reasoning or the failure that produced this — enough to judge an edge case the
Knowledge section does not cover. Not a narrative of the session.>

## Boundaries

<Where this stops applying: versions, platforms, configurations, or conditions under which it is
known to be false or untested. An Understanding with no stated boundary will be over-applied.>

## Provenance

<What it was learned from, in one or two lines. Name the artifact where one exists — a failing
command, an upstream issue, a PR. No secrets or credential values: this file is exportable.>

## Changelog

| Date | Change |
|:-----|:-------|
| <YYYY-MM-DD> | Encoded. |
