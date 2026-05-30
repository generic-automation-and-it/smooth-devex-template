"""
Claude Code PostToolUse hook – slnx-docs-sync
Mirrors the OpenCode plugin at .opencode/plugins/slnx-docs-sync.ts.

Keeps *.slnx in sync when NFR or ADR documents are created
or edited by a Write/Edit/NotebookEdit tool call.

Receives a JSON payload on stdin from Claude Code:
  {
    "tool_name": "Write" | "Edit" | ...,
    "tool_input": { "file_path": "<absolute path>" },
    ...
  }
"""

import glob
import json
import os
import re
import sys


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    tool_input = data.get("tool_input", {})
    file_path: str = tool_input.get("file_path", "")
    if not file_path:
        sys.exit(0)

    # Claude Code hooks run with cwd = project root.
    repo_root = os.getcwd()

    try:
        rel = os.path.relpath(file_path, repo_root).replace("\\", "/")
    except ValueError:
        # Paths on different drives — skip.
        sys.exit(0)

    # Map path prefix to the matching .slnx solution folder.
    if rel.startswith(".docs/adr/"):
        folder_name = "/.docs/adr/"
    elif rel.startswith(".docs/nfr/"):
        folder_name = "/.docs/nfr/"
    else:
        sys.exit(0)

    slnx_files = glob.glob(os.path.join(repo_root, "*.slnx"))
    if not slnx_files:
        sys.exit(0)
    slnx_path = slnx_files[0]
    try:
        content = open(slnx_path, encoding="utf-8").read()
    except OSError:
        sys.exit(0)

    file_entry = f'<File Path="{rel}" />'

    # Already present — nothing to do.
    if file_entry in content:
        sys.exit(0)

    # Locate the target <Folder> element.
    folder_tag = f'<Folder Name="{folder_name}">'
    folder_idx = content.find(folder_tag)
    if folder_idx == -1:
        sys.exit(0)

    # Find the corresponding </Folder> closing tag.
    closing_tag = "</Folder>"
    search_start = folder_idx + len(folder_tag)
    closing_idx = content.find(closing_tag, search_start)
    if closing_idx == -1:
        sys.exit(0)

    # Match the indentation of the closing tag and add two extra spaces.
    line_start = content.rfind("\n", 0, closing_idx) + 1
    m = re.match(r"^(\s*)", content[line_start:closing_idx])
    indent = m.group(1) if m else ""
    entry_indent = indent + "  "

    updated = (
        content[:closing_idx]
        + f"{entry_indent}{file_entry}\n"
        + content[closing_idx:]
    )
    open(slnx_path, "w", encoding="utf-8").write(updated)
    print(f"slnx-docs-sync: added {rel} → {folder_name}", file=sys.stderr)


if __name__ == "__main__":
    main()
