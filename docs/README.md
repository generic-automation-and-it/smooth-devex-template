# Docs

Reviewer-facing documentation. AI-coder context lives in `AGENTS.md` / `*AGENTS.md`, not here.

| Path | Holds |
|---|---|
| [`wiki/`](wiki/) | How-to and reference: local dev, testing, CI, architecture, AI tooling, reuse, asset sync |
| [`examples/`](examples/) | Copy-paste consumer files (e.g. AI asset sync caller workflow) |
| [`adr/`](adr/) | Architecture Decision Records — foundational decisions (promoted from HLD LADRs) |
| [`hlds/`](hlds/) | High-Level Designs from the `create-hld` skill (`NNN-<slug>/` folders: intent + spec, no implementation; NFRs live per-design under `nfrs/`) |

Conventions: `create-hld` authors `hlds/NNN-<slug>/`; `create-worktask` links applicable records from `hlds/` and `adr/`, keeping decisions in their existing home. `Project.slnx` registers each file individually — register what you add (see `docs/wiki/ai-tooling.md`).
