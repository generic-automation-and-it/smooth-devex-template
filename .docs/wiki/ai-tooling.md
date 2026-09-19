# AI Tooling

## Approach

The development of this solution deliberately demonstrates an AI-agnostic approach to developer tooling. The goal was not to pick a favourite — it was to understand what each tool and its underlying models are genuinely best suited for across a real delivery.

## Tools Used

| Tool | Primary Role |
|---|---|
| **Claude Code** (Anthropic) | Spec-driven generation, architectural reasoning, primary code authoring |
| **OpenAI Codex** | Code generation, pull request workflow automation, agentic task execution |
| **GitHub Copilot** (web agent) | In-editor assistance, agentic task execution, pull request review participation |

All three tools share a common context through the `.agents/` folder — rules, conventions, and prompt templates are maintained in one place and symlinked per tool.

## Key Findings

- Cross-model review (writing with one tool, reviewing with another) caught assumptions and patterns the authoring model would have missed.
- Claude Code performed strongest on spec-to-code generation when given structured HLDs and NFRs.
- Codex was well-suited to PR workflow automation and repetitive generation tasks.
- GitHub Copilot's web agent added value in PR review participation — visible in the PR conversation history.

## Embedded AI Agent

A Claude SDK-powered conversational agent is embedded directly in the API. It allows natural-language queries against the buildability data — for example: *"Which sets can brickfan35 build?"* — rather than requiring direct API calls. This was a deliberate side quest to explore agentic integration as a pattern for data-rich APIs.

## Recommendations (for teams adopting this approach)

- Run AI reviews alongside linters — they serve different purposes.
- Use a different model for review than for authoring. Cross-model review is more effective.
- Invest in shared context files (`.agents/` equivalent) early. All tools benefit from a single source of truth on conventions and domain knowledge.

## Setup

See the `.agents/` folder for full configuration. Run the appropriate setup script after cloning to recreate symlink aliases:

```bash
# Mac / Linux
bash .agents/setup/scripts/agents-setup.sh

# Windows (PowerShell — run as Administrator)
.\.agents\setup\scripts\agents-setup.ps1
```

## AI asset sync

Scheduled OpenCode reconciler for skills/rules. Consumer manifest `.github/assets/ai-sync.yml`, reusable workflow + composite action, skill entrypoint `.agents/skills/ai-asset-sync/scripts/run-sync.sh`. See [AI Asset Sync](ai-asset-sync.md).

## Understandings

Agent memory as a reviewable artifact. An *Understanding* is a distilled unit of discovered knowledge — a non-obvious root cause, an environment quirk, a convention invisible in the code — written so a future agent with none of the originating context can act on it.

They accrue locally in `.context/understandings/<slug>/` (gitignored, one folder per unit so evidence files never collide), and reach the repository only through an approved export of the units marked `scope: portable`. That split is the point: encoding stays cheap enough that agents propose freely, while shared memory stays small because review happens once, later, when it is clear which knowledge held up. Exported Understandings travel between repositories over the same `ai-asset-sync` transport as skills and rules.

Understandings are evidence, not orders — a rule always wins a conflict, and an Understanding contradicted by the code is flagged rather than applied. Skill: `.agents/skills/ai-understanding/`; governance: `.agents/rules/meta/understandings.instructions.md`.

## Further Reading

- [Architecture](architecture.md) — solution structure and design decisions
- [Testing Strategy](testing.md) — test levels and infrastructure
