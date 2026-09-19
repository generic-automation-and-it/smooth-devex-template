#!/usr/bin/env python3
"""Regenerate the Understandings INDEX.md from the subject/slug folders.

The store is two levels deep — `<subject>/<slug>/UNDERSTANDING.md` — so a session's
lessons stay browsable together while each one remains individually addressable by its
trigger. The index groups by subject but lists every leaf, because knowledge is retrieved
by trigger rather than by the subject that happened to produce it.

The index is a reference table, never a copy of the knowledge: an agent reads it to decide
which Understandings to load, then reads only those folders.

Usage:
    python3 .agents/skills/ai-understanding/scripts/understanding_index.py [store-dir]

Defaults to `.context/understandings`. Pure standard library, read/write only, no network.
Exits 1 when a unit fails validation — the index is still written so the drift is visible.
"""

from __future__ import annotations

import sys
from pathlib import Path

DEFAULT_STORE = Path(".context/understandings")
UNIT_FILENAME = "UNDERSTANDING.md"
REQUIRED_FIELDS = ("slug", "description", "trigger", "scope", "confidence")
VALID_SCOPES = ("portable", "repo-specific")
VALID_CONFIDENCE = ("observed", "verified", "contested")
UNFILED = "_unfiled"


def parse_frontmatter(text: str) -> dict:
    """Parse this format: flat scalars, lists, a nested map, and a list inside that map.

    Deep enough for `provenance.inherited`; anything deeper needs extending here, not just
    the template.
    """
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}

    data: dict = {}
    parent: str | None = None   # top-level key holding a map or list
    child: str | None = None    # key inside that map holding a list

    for line in lines[1:]:
        if line.strip() == "---":
            break
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        if not line[:1].isspace():
            key, _, value = stripped.partition(":")
            if not _:
                continue
            key, value = key.strip(), value.strip()
            child = None
            if value:
                data[key] = value
                parent = None
            else:
                data[key] = {}
                parent = key
            continue

        if parent is None:
            continue

        if stripped.startswith("- "):
            item = stripped[2:].strip()
            if child is not None:
                data[parent].setdefault(child, []).append(item)
            else:
                if not isinstance(data.get(parent), list):
                    data[parent] = []
                data[parent].append(item)
            continue

        key, _, value = stripped.partition(":")
        if not _:
            continue
        key, value = key.strip(), value.strip()
        if not isinstance(data.get(parent), dict):
            data[parent] = {}
        if value:
            data[parent][key] = value
            child = None
        else:
            data[parent][key] = []
            child = key

    return data


def placeholder(value: str) -> bool:
    return value.startswith("<") and value.endswith(">")


def read_unit(unit_dir: Path, subject: str) -> tuple[dict | None, list[str]]:
    """Load and validate one `<subject>/<slug>/UNDERSTANDING.md`."""
    where = f"{subject}/{unit_dir.name}"
    unit_file = unit_dir / UNIT_FILENAME

    if not unit_file.is_file():
        return None, [f"{where}/ has no {UNIT_FILENAME}"]

    fields = parse_frontmatter(unit_file.read_text(encoding="utf-8"))
    if not fields:
        return None, [f"{where}/{UNIT_FILENAME} has no frontmatter"]

    problems = []
    for field in REQUIRED_FIELDS:
        value = fields.get(field)
        if not isinstance(value, str) or not value or placeholder(value):
            problems.append(f"{where}: '{field}' is missing or still a placeholder")

    updated = fields.get("updated")
    if not isinstance(updated, str) or not updated or placeholder(updated):
        problems.append(f"{where}: 'updated' is missing or still a placeholder")

    provenance = fields.get("provenance")
    if not isinstance(provenance, dict) or not provenance:
        problems.append(f"{where}: 'provenance' is missing")
    else:
        for key in ("learned", "session", "source"):
            value = provenance.get(key)
            if not value or placeholder(value):
                problems.append(f"{where}: 'provenance.{key}' is missing or still a placeholder")

    context = fields.get("agents_context")
    if isinstance(context, str) and context and not placeholder(context):
        if not Path(context).exists():
            problems.append(f"{where}: agents_context '{context}' does not exist")

    if fields.get("slug") not in (unit_dir.name, None):
        problems.append(f"{where}: slug '{fields['slug']}' does not match the folder name")
    if isinstance(fields.get("scope"), str) and fields["scope"] not in VALID_SCOPES:
        problems.append(f"{where}: scope '{fields['scope']}' is not one of {VALID_SCOPES}")
    if isinstance(fields.get("confidence"), str) and fields["confidence"] not in VALID_CONFIDENCE:
        problems.append(f"{where}: confidence '{fields['confidence']}' is not one of {VALID_CONFIDENCE}")

    fields["folder"] = unit_dir.name
    fields["subject"] = subject
    fields["path"] = f"{subject}/{unit_dir.name}"
    return fields, problems


def load_units(store: Path) -> tuple[list[dict], list[str]]:
    units: list[dict] = []
    problems: list[str] = []

    for subject_dir in sorted(p for p in store.iterdir() if p.is_dir()):
        if (subject_dir / UNIT_FILENAME).is_file():
            problems.append(
                f"{subject_dir.name}/ holds a unit directly — move it to "
                f"<subject>/{subject_dir.name}/ (use '{UNFILED}' when it belongs to no subject)"
            )
            continue

        unit_dirs = sorted(p for p in subject_dir.iterdir() if p.is_dir())
        if not unit_dirs:
            problems.append(f"{subject_dir.name}/ contains no Understanding folders")
            continue

        for unit_dir in unit_dirs:
            unit, unit_problems = read_unit(unit_dir, subject_dir.name)
            problems.extend(unit_problems)
            if unit:
                units.append(unit)

    problems.extend(duplicate_slugs(units))
    problems.extend(dangling_links(units))
    problems.extend(dangling_inherited(units))
    return units, problems


def duplicate_slugs(units: list[dict]) -> list[str]:
    """Leaf slugs address an Understanding from anywhere, so they must be unique store-wide."""
    seen: dict[str, str] = {}
    duplicates = []
    for unit in units:
        slug = unit["folder"]
        if slug in seen:
            duplicates.append(f"slug '{slug}' appears in both {seen[slug]}/ and {unit['subject']}/")
        else:
            seen[slug] = unit["subject"]
    return duplicates


def dangling_links(units: list[dict]) -> list[str]:
    known = {unit["folder"] for unit in units}
    dangling = []
    for unit in units:
        links = unit.get("links")
        if not isinstance(links, list):
            continue
        for link in links:
            target = link.strip().strip("[]")
            if target and not placeholder(target) and target not in known:
                dangling.append(f"{unit['path']}: link [[{target}]] has no matching folder")
    return dangling


def dangling_inherited(units: list[dict]) -> list[str]:
    """`provenance.inherited` records the lineage a session actually acted on.

    A bracketed entry is a live reference and must resolve. Drop the brackets to record an
    ancestor that has since been pruned or promoted away — the lineage stays readable
    without pinning the store to knowledge it no longer holds.
    """
    known = {unit["folder"] for unit in units}
    dangling = []
    for unit in units:
        provenance = unit.get("provenance")
        if not isinstance(provenance, dict):
            continue
        for entry in provenance.get("inherited") or []:
            entry = entry.strip()
            if not entry.startswith("[[") or placeholder(entry):
                continue
            target = entry.strip("[]")
            if target and target not in known:
                dangling.append(
                    f"{unit['path']}: inherited [[{target}]] is no longer in the store — "
                    f"restore it, point at what superseded it, or unbracket it to keep the lineage"
                )
    return dangling


def cell(value) -> str:
    if not isinstance(value, str) or not value:
        return "—"
    return value.replace("|", "\\|")


def render(units: list[dict]) -> str:
    lines = [
        "# Understandings — INDEX",
        "",
        "Generated by `.agents/skills/ai-understanding/scripts/understanding_index.py`. Do not hand-edit.",
        "",
        "Grouped by subject for browsing; every Understanding is listed individually because knowledge is",
        "retrieved by **trigger**, not by the subject that produced it. Match a trigger against the task at",
        "hand, then read only the folders that matched.",
        "",
    ]

    if not units:
        lines += ["_No Understandings encoded yet._", ""]
        return "\n".join(lines)

    subjects: dict[str, list[dict]] = {}
    for unit in units:
        subjects.setdefault(unit["subject"], []).append(unit)

    for subject in sorted(subjects):
        lines += [
            f"## {subject}",
            "",
            "| Folder | Description | Trigger | Scope | Confidence | Updated |",
            "|--------|-------------|---------|-------|------------|---------|",
        ]
        for unit in subjects[subject]:
            path = unit["path"]
            lines.append(
                f"| [`{unit['folder']}/`](./{path}/) | {cell(unit.get('description'))} "
                f"| {cell(unit.get('trigger'))} | {cell(unit.get('scope'))} "
                f"| {cell(unit.get('confidence'))} | {cell(unit.get('updated'))} |"
            )
        lines.append("")
    return "\n".join(lines)


USAGE = f"""usage: understanding_index.py [store-dir]

Regenerate INDEX.md from the <subject>/<slug>/{UNIT_FILENAME} folders.
Defaults to {DEFAULT_STORE}.

Exit codes: 0 clean · 1 validation problems (index still written) · 2 store not found."""


def main(argv: list[str]) -> int:
    args = argv[1:]
    if any(a in ("-h", "--help") for a in args):
        print(USAGE)
        return 0
    unknown = [a for a in args if a.startswith("-")]
    if unknown:
        print(f"unknown option: {unknown[0]}\n\n{USAGE}", file=sys.stderr)
        return 2
    if len(args) > 1:
        print(f"expected at most one store-dir, got {len(args)}\n\n{USAGE}", file=sys.stderr)
        return 2

    store = Path(args[0]) if args else DEFAULT_STORE
    if not store.is_dir():
        print(f"store not found: {store}", file=sys.stderr)
        return 2

    units, problems = load_units(store)
    (store / "INDEX.md").write_text(render(units), encoding="utf-8")
    subject_count = len({unit["subject"] for unit in units})
    print(
        f"indexed {len(units)} understanding(s) across {subject_count} subject(s) "
        f"-> {store / 'INDEX.md'}"
    )

    for problem in problems:
        print(f"  problem: {problem}", file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
