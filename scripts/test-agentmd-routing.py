import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
HOOK = REPO / ".agents/hooks/agentmd-create-update.sh"


class AgentmdRoutingTests(unittest.TestCase):
    def run_hook(self, payload, hook=HOOK, cwd=None):
        result = subprocess.run(
            ["bash", str(hook)], input=payload, cwd=cwd,
            capture_output=True, text=True, timeout=5,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_authoring_requests_route_to_the_skill(self):
        prompts = (
            "create agent.md", "create agents.md", "create an agent.md",
            "create an agents.md", "update agents.md", "update agent.md",
            "Please edit AGENTS.md", "revise docs/auth/AUTH_AGENTS.md",
            "\n\n  CREATE a docs/hlds/001-auth/AGENTS.md\nDetails",
            'update "src/auth/AGENTS.md": document the invariant',
        )
        expected = REPO / ".agents/skills/agentmd-create-update/SKILL.md"
        for prompt in prompts:
            with self.subTest(prompt=prompt):
                output = self.run_hook(json.dumps({"prompt": prompt}))
                self.assertIn(str(expected), output)
                self.assertNotIn("## Required Structure", output)

    def test_non_requests_and_invalid_payloads_are_silent(self):
        prompts = (
            "How do I create agents.md?", "Should we update agent.md?",
            "Don't create agents.md yet", "Review this:\ncreate agents.md",
            "$agentmd-create-update AGENTS.md", "/agentmd-create-update AGENTS.md",
            "create agents.md.bak", "update agents.md_template", "create worktask",
        )
        payloads = [json.dumps({"prompt": prompt}) for prompt in prompts]
        payloads += ["", "not json", "{}", '{"prompt": null}', '{"prompt": ""}',
                     '{"prompt": ["create agents.md"]}', '{"prompt": 123}']
        for payload in payloads:
            with self.subTest(payload=payload):
                self.assertEqual(self.run_hook(payload), "")

    def test_installed_hook_resolves_skill_independently_of_working_directory(self):
        with tempfile.TemporaryDirectory(prefix="agentmd-routing-") as scratch:
            root = Path(scratch)
            store = root / "global store"
            hook = store / "hooks" / HOOK.name
            hook.parent.mkdir(parents=True)
            shutil.copy2(HOOK, hook)
            caller = root / "unrelated repository"
            caller.mkdir()
            output = self.run_hook('{"prompt": "create agents.md"}', hook, caller)
            self.assertIn(str(store / "skills/agentmd-create-update/SKILL.md"), output)
            self.assertFalse(any(caller.iterdir()))


if __name__ == "__main__":
    unittest.main()
