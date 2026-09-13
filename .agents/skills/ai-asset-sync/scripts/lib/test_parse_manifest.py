#!/usr/bin/env python3
"""Stdlib tests for parse_manifest.py. Run directly:

  python3 .agents/skills/ai-asset-sync/scripts/lib/test_parse_manifest.py
"""
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent


def load():
    spec = importlib.util.spec_from_file_location("parse_manifest", SCRIPTS / "parse_manifest.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


pm = load()


class ParseSourceTests(unittest.TestCase):
    def test_happy(self):
        p = pm.parse_source("acme/tools@v1:.agents/skills/ai-brain-dump")
        self.assertEqual(p["owner"], "acme")
        self.assertEqual(p["repo"], "tools")
        self.assertEqual(p["ref"], "v1")
        self.assertEqual(p["path"], ".agents/skills/ai-brain-dump")

    def test_ref_with_slash_not_supported_as_path_split(self):
        p = pm.parse_source("acme/tools@main:.github/instructions/git/git-policy.instructions.md")
        self.assertEqual(p["ref"], "main")
        self.assertEqual(p["path"], ".github/instructions/git/git-policy.instructions.md")

    def test_sha_ref(self):
        p = pm.parse_source("acme/tools@deadbeef:.agents/skills/x")
        self.assertEqual(p["ref"], "deadbeef")

    def test_rejects_parent_path(self):
        with self.assertRaises(pm.ManifestError):
            pm.parse_source("acme/tools@main:../secrets")

    def test_rejects_missing_path(self):
        with self.assertRaises(pm.ManifestError):
            pm.parse_source("acme/tools@main")

    def test_rejects_absolute(self):
        with self.assertRaises(pm.ManifestError):
            pm.parse_source("acme/tools@main:/etc/passwd")


class ParseManifestTests(unittest.TestCase):
    def test_two_entries_default_strategy(self):
        text = """
version: 1
entries:
  - source: acme/tools@main:.agents/skills/ai-brain-dump
  - source: acme/tools@v1:.agents/rules/git
    strategy: overwrite
"""
        data = pm.parse_manifest(text)
        self.assertEqual(len(data["entries"]), 2)
        self.assertEqual(data["entries"][0]["strategy"], "ai-merge")
        self.assertEqual(data["entries"][1]["strategy"], "overwrite")

    def test_empty_entries(self):
        data = pm.parse_manifest("version: 1\nentries: []\n")
        self.assertEqual(data["entries"], [])

    def test_duplicate_source(self):
        text = """
entries:
  - source: acme/tools@main:.agents/skills/x
  - source: acme/tools@main:.agents/skills/x
"""
        with self.assertRaises(pm.ManifestError):
            pm.parse_manifest(text)

    def test_bad_strategy(self):
        text = """
entries:
  - source: acme/tools@main:.agents/skills/x
    strategy: merge
"""
        with self.assertRaises(pm.ManifestError):
            pm.parse_manifest(text)

    def test_comments_ignored(self):
        text = """
# consumer manifest
entries:
  - source: acme/tools@main:.agents/skills/x  # keep
"""
        data = pm.parse_manifest(text)
        self.assertEqual(data["entries"][0]["path"], ".agents/skills/x")


class LockfileTests(unittest.TestCase):
    def test_roundtrip(self):
        entries = [
            {
                "source": "acme/tools@main:.agents/skills/x",
                "resolved_sha": "abc1234",
                "synced_at": "2026-09-13T06:00:00Z",
            }
        ]
        dumped = pm.dump_lockfile(entries)
        parsed = pm.parse_lockfile(dumped)
        self.assertEqual(parsed["entries"][0]["resolved_sha"], "abc1234")

    def test_empty_lockfile(self):
        self.assertEqual(pm.parse_lockfile("")["entries"], [])

    def test_index_by_source(self):
        lock = pm.parse_lockfile(
            "version: 1\nentries:\n  - source: acme/tools@main:.agents/skills/x\n    resolved_sha: abcdef0\n"
        )
        idx = pm.lockfile_index(lock)
        self.assertEqual(idx["acme/tools@main:.agents/skills/x"]["resolved_sha"], "abcdef0")


if __name__ == "__main__":
    unittest.main()
