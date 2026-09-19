#!/usr/bin/env python3
"""Regenerate the Understandings INDEX.md from the subject/slug folders.

The store is `<subject>/<slug>.md` — a subject folder groups a session's lessons while each
file stays individually addressable by its trigger. The index groups by subject but lists
every unit, because knowledge is retrieved by trigger rather than by the subject that
happened to produce it.

A unit needing evidence artifacts (a repro, a log excerpt, a diagram) puts them in a
sibling `<slug>.assets/` directory, which is named after the slug and so cannot collide.

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
ASSETS_SUFFIX = ".assets"
LEGACY_UNIT_FILENAME = "UNDERSTANDING.md"
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


def read_unit(unit_file: Path, subject: str) -> tuple[dict | None, list[str]]:
    """Load and validate one `<subject>/<slug>.md`."""
    slug = unit_file.stem
    where = f"{subject}/{unit_file.name}"

    fields = parse_frontmatter(unit_file.read_text(encoding="utf-8"))
    if not fields:
        return None, [f"{where} has no frontmatter"]

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

    if fields.get("slug") not in (slug, None):
        problems.append(f"{where}: slug '{fields['slug']}' does not match the file name")
    if isinstance(fields.get("scope"), str) and fields["scope"] not in VALID_SCOPES:
        problems.append(f"{where}: scope '{fields['scope']}' is not one of {VALID_SCOPES}")
    if isinstance(fields.get("confidence"), str) and fields["confidence"] not in VALID_CONFIDENCE:
        problems.append(f"{where}: confidence '{fields['confidence']}' is not one of {VALID_CONFIDENCE}")

    fields["folder"] = slug
    fields["subject"] = subject
    fields["path"] = f"{subject}/{unit_file.name}"
    return fields, problems


def load_units(store: Path) -> tuple[list[dict], list[str]]:
    units: list[dict] = []
    problems: list[str] = []

    for stray in sorted(store.glob("*.md")):
        if stray.name != "INDEX.md":
            problems.append(
                f"{stray.name} sits at the store root — move it to <subject>/{stray.name} "
                f"(use '{UNFILED}' when it belongs to no subject)"
            )

    for subject_dir in sorted(p for p in store.iterdir() if p.is_dir()):
        subject = subject_dir.name

        for legacy in sorted(subject_dir.glob(f"*/{LEGACY_UNIT_FILENAME}")):
            problems.append(
                f"{subject}/{legacy.parent.name}/ uses the old folder shape — move it to "
                f"{subject}/{legacy.parent.name}.md (artifacts go in "
                f"{legacy.parent.name}{ASSETS_SUFFIX}/)"
            )

        unit_files = sorted(subject_dir.glob("*.md"))
        if not unit_files:
            problems.append(f"{subject}/ contains no Understandings")
            continue

        for unit_file in unit_files:
            unit, unit_problems = read_unit(unit_file, subject)
            problems.extend(unit_problems)
            if unit:
                units.append(unit)

    problems.extend(duplicate_slugs(units))
    problems.extend(dangling_references(units))
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


def iter_reference_fields(unit: dict):
    """Yield every (field-path, list) in a unit's frontmatter that could hold `[[slug]]` refs.

    Walks the shape generically — top-level lists and lists one level inside a map — so a
    field added to the template is validated without touching this file. Parsing was already
    generic; validation used to be per-field, and a new field went silently unchecked.
    """
    for key, value in unit.items():
        if key in ("folder", "subject", "path"):
            continue
        if isinstance(value, list):
            yield key, value
        elif isinstance(value, dict):
            for sub_key, sub_value in value.items():
                if isinstance(sub_value, list):
                    yield f"{key}.{sub_key}", sub_value


# How to word an unresolvable reference, per field. Any field not listed gets the default.
REFERENCE_REMEDIES = {
    "provenance.inherited": (
        "is no longer in the store — restore it, point at what superseded it, "
        "or unbracket it to keep the lineage"
    ),
}
DEFAULT_REMEDY = "has no matching Understanding"


def dangling_references(units: list[dict]) -> list[str]:
    """An unresolvable `[[slug]]` in any frontmatter list, wherever it appears.

    Only bracketed entries are references. A bare string is a historical note — that is how a
    lineage survives the Understanding it names being pruned or promoted away.
    """
    known = {unit["folder"] for unit in units}
    dangling = []
    for unit in units:
        for field, values in iter_reference_fields(unit):
            for entry in values:
                entry = str(entry).strip()
                if not entry.startswith("[[") or placeholder(entry):
                    continue
                target = entry.strip("[]")
                if target and target not in known:
                    remedy = REFERENCE_REMEDIES.get(field, DEFAULT_REMEDY)
                    dangling.append(f"{unit['path']}: {field} [[{target}]] {remedy}")
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
        "hand, then read only the units that matched.",
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
            "| Understanding | Description | Trigger | Scope | Confidence | Updated |",
            "|---------------|-------------|---------|-------|------------|---------|",
        ]
        for unit in subjects[subject]:
            path = unit["path"]
            lines.append(
                f"| [`{unit['folder']}`](./{path}) | {cell(unit.get('description'))} "
                f"| {cell(unit.get('trigger'))} | {cell(unit.get('scope'))} "
                f"| {cell(unit.get('confidence'))} | {cell(unit.get('updated'))} |"
            )
        lines.append("")
    return "\n".join(lines)


USAGE = f"""usage: understanding_index.py [store-dir]

Regenerate INDEX.md from the <subject>/<slug>.md units.
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
