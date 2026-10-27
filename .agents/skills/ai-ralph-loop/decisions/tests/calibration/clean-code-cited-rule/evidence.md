Cited rule, `.github/instructions/clean-code.instructions.md`, section Names (excerpt): "**No type or container in the name** — `name`, not `nameString`; `events`, not `eventsList`."

Failure scenario: `findingsList` carries the container type and `findingString` carries the element type in their names, which the rule forbids.

Fix: rename them to `findings` and `finding`; behaviour is unchanged.
