#!/usr/bin/env python3

import json
from pathlib import Path
import shutil
import subprocess
import unittest


HOOK = Path(__file__).resolve().parents[1] / ".agents/hooks/worktask-skill-trigger.sh"


class WorktaskRoutingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        for dependency in ("bash", "jq"):
            if shutil.which(dependency) is None:
                raise RuntimeError(f"Requires {dependency} on PATH")

    def run_hook(self, payload):
        result = subprocess.run(
            ["bash", str(HOOK)],
            input=payload,
            capture_output=True,
            text=True,
            check=False,
            timeout=5,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_imperative_worktask_requests_route_to_skill(self):
        prompts = (
            "create worktask for login",
            "create a work task for login",
            "make a work-task for login",
            "please create an SDLC worktask for login",
            "Create SDLC work task: login",
            "make an sdlc work-task for login",
            "promote this to a worktask",
            "please promote this to an SDLC work-task",
            "\n\n  create an SDLC worktask\nAdditional requirements",
        )
        for prompt in prompts:
            with self.subTest(prompt=prompt):
                output = self.run_hook(json.dumps({"prompt": prompt}))
                self.assertIn(".agents/skills/create-worktask/SKILL.md", output)

    def test_questions_direct_calls_and_other_artifacts_do_not_route(self):
        prompts = (
            "how does create worktask work?",
            "Should we create an SDLC worktask?",
            "Can you create a worktask?",
            "create an SDLC implementation plan",
            "create a design for the SDLC",
            "promote this to a feature",
            "$create-worktask login",
            "/create-worktask login",
            "Review this request:\ncreate an SDLC worktask",
            "create a worktask-template",
            "create a worktask_archive",
            "create a worktasking example",
        )
        for prompt in prompts:
            with self.subTest(prompt=prompt):
                self.assertEqual(self.run_hook(json.dumps({"prompt": prompt})), "")

    def test_missing_empty_and_invalid_payloads_are_silent(self):
        for payload in ("", "not json", "{}", '{"prompt": ""}', '{"prompt": null}'):
            with self.subTest(payload=payload):
                self.assertEqual(self.run_hook(payload), "")


if __name__ == "__main__":
    unittest.main()
