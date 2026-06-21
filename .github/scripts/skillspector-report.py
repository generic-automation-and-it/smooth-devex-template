#!/usr/bin/env python3
"""Render a SkillSpector JSON report into a GitHub job summary (stdout) and SARIF.

SkillSpector emits one --format per run, and its native SARIF is minimal (no
risk score, category, or confidence). The JSON report carries everything, so we
scan once with --format json and derive both artifacts here:

  - Markdown summary -> stdout (redirect into $GITHUB_STEP_SUMMARY)
  - SARIF 2.1.0      -> <sarif_out> (for GitHub code scanning, when enabled)

Usage: skillspector-report.py <report.json> <out.sarif> [path_prefix]

`path_prefix` (default ".agents/skills") is prepended to each finding's file so
SARIF locations resolve from the repo root. Missing/empty JSON (e.g. SkillSpector
errored before writing) is handled gracefully: a note is emitted and an empty
SARIF is written so the upload step has a valid file.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

# SkillSpector severity -> (SARIF level, GitHub security-severity numeric)
LEVEL = {"CRITICAL": "error", "HIGH": "error", "MEDIUM": "warning", "LOW": "note"}
SECSEV = {"CRITICAL": "9.5", "HIGH": "8.0", "MEDIUM": "5.0", "LOW": "2.0"}
SEV_ORDER = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3}
EMOJI = {"CRITICAL": "🟥", "HIGH": "🟧", "MEDIUM": "🟨", "LOW": "🟦"}


def empty_sarif() -> dict:
    return {
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        "version": "2.1.0",
        "runs": [
            {
                "tool": {
                    "driver": {
                        "name": "SkillSpector",
                        "informationUri": "https://github.com/NVIDIA/SkillSpector",
                        "rules": [],
                    }
                },
                "results": [],
            }
        ],
    }


def build_sarif(report: dict, prefix: str) -> dict:
    issues = report.get("issues") or []
    version = (report.get("metadata") or {}).get("skillspector_version")
    rules: dict[str, dict] = {}
    results = []
    for it in issues:
        rid = it.get("id") or "UNKNOWN"
        sev = (it.get("severity") or "MEDIUM").upper()
        if rid not in rules:
            rules[rid] = {
                "id": rid,
                "name": (it.get("category") or rid).replace(" ", ""),
                "shortDescription": {"text": it.get("category") or rid},
                "fullDescription": {"text": it.get("explanation") or it.get("pattern") or rid},
                "helpUri": "https://github.com/NVIDIA/SkillSpector",
                "properties": {
                    "security-severity": SECSEV.get(sev, "5.0"),
                    "tags": [t for t in [it.get("category")] if t],
                },
            }
        loc = it.get("location") or {}
        f = loc.get("file")
        uri = f"{prefix.rstrip('/')}/{f}" if f else (f or "")
        region = {}
        if loc.get("start_line"):
            region["startLine"] = loc["start_line"]
        if loc.get("end_line"):
            region["endLine"] = loc["end_line"]
        physical = {"artifactLocation": {"uri": uri}}
        if region:
            physical["region"] = region
        results.append(
            {
                "ruleId": rid,
                "level": LEVEL.get(sev, "warning"),
                "message": {"text": f"[{sev}] {it.get('pattern') or it.get('category') or rid}: {it.get('explanation') or ''}".strip()},
                "locations": [{"physicalLocation": physical}],
            }
        )
    driver = {
        "name": "SkillSpector",
        "informationUri": "https://github.com/NVIDIA/SkillSpector",
        "rules": list(rules.values()),
    }
    if version:
        driver["version"] = version
    return {
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        "version": "2.1.0",
        "runs": [{"tool": {"driver": driver}, "results": results}],
    }


def build_summary(report: dict) -> str:
    ra = report.get("risk_assessment") or {}
    score = ra.get("score")
    sev = (ra.get("severity") or "?").upper()
    reco = ra.get("recommendation") or "?"
    issues = report.get("issues") or []
    meta = report.get("metadata") or {}
    llm = "LLM semantic + static" if meta.get("llm_available") else "static-only"

    counts: dict[str, int] = {}
    for it in issues:
        s = (it.get("severity") or "?").upper()
        counts[s] = counts.get(s, 0) + 1
    breakdown = ", ".join(
        f"{counts[s]} {s}" for s in sorted(counts, key=lambda x: SEV_ORDER.get(x, 9))
    ) or "none"

    out = []
    out.append("## 🛡️ SkillSpector scan")
    out.append("")
    badge = EMOJI.get(sev, "⬜")
    out.append(f"{badge} **Risk score: {score}/100 — {sev} — {reco}**")
    out.append("")
    out.append(f"**{len(issues)} findings** ({breakdown}) · analysis: {llm}")
    out.append("")
    if issues:
        out.append("| Sev | ID | Category | Pattern | Location | Conf |")
        out.append("|-----|----|----------|---------|----------|------|")
        for it in sorted(issues, key=lambda i: SEV_ORDER.get((i.get("severity") or "").upper(), 9)):
            loc = it.get("location") or {}
            where = loc.get("file", "?")
            if loc.get("start_line"):
                where += f":{loc['start_line']}"
            conf = it.get("confidence")
            conf_s = f"{conf:.0%}" if isinstance(conf, (int, float)) else ""
            out.append(
                f"| {(it.get('severity') or '?').upper()} | {it.get('id','')} | "
                f"{it.get('category','')} | {it.get('pattern','')} | `{where}` | {conf_s} |"
            )
    out.append("")
    return "\n".join(out)


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: skillspector-report.py <report.json> <out.sarif> [path_prefix]", file=sys.stderr)
        return 2
    json_in, sarif_out = sys.argv[1], sys.argv[2]
    prefix = sys.argv[3] if len(sys.argv) > 3 else ".agents/skills"

    p = Path(json_in)
    if not p.exists() or p.stat().st_size == 0:
        Path(sarif_out).write_text(json.dumps(empty_sarif()))
        print("## 🛡️ SkillSpector scan\n\n⚠️ No JSON report produced — the scan likely errored before completing. See the scan step log.\n")
        return 0

    report = json.loads(p.read_text())
    Path(sarif_out).write_text(json.dumps(build_sarif(report, prefix)))
    print(build_summary(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
