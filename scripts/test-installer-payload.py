import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


REPO = Path(__file__).resolve().parent.parent
TEST_FILES = ("test_main.py", "main_test.py", "main.test.js", "main.Tests.ps1")
TEST_DIRS = ("test", "tests", "__tests__")
PORTS = ("bash",)


class InstallerPayloadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory(prefix="installer-payload-")
        cls.addClassCleanup(cls.scratch.cleanup)
        cls.root = Path(cls.scratch.name)
        cls.source = cls.root / "source"
        cls.source.mkdir()
        cls.outside = cls.root / "outside.txt"
        cls.outside.write_text("operator-owned\n")
        cls.outside_dir = cls.root / "outside-dir"
        cls.outside_dir.mkdir()
        (cls.outside_dir / "test_main.py").write_text("operator test\n")

        def write(relative, content):
            path = cls.source / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
            return path

        write("payload/reference.md", "reference\n")
        write("payload/references/nested.md", "nested\n")
        write("payload/references/reference.md", "indirect reference\n")
        write("payload/references/deep/keep.md", "deep\n")
        (cls.source / "payload/alias").symlink_to("references/deep")
        write("payload/a/keep.md", "a\n")
        write("payload/b/keep.md", "b\n")
        (cls.source / "payload/a/next").symlink_to("../b")
        (cls.source / "payload/b/next").symlink_to("../a")
        write("payload/rule.md", "---\napplyTo: '**'\n---\n# Policy\n")
        write("payload/hook.sh", "#!/bin/sh\nexit 0\n").chmod(0o755)
        skill = write(".agents/skills/alpha/SKILL.md", "# Alpha\n").parent
        write(".agents/skills/alpha/AGENTS.md", "owner context\n")
        write(".agents/skills/alpha/scripts/main.py", "print('runtime')\n")
        write(".agents/skills/alpha/scripts/test_nested.py", "test\n")
        write(".agents/skills/alpha/..hidden.md", "hidden\n")
        for name, target in {
            "reference.md": "../../../payload/reference.md",
            "indirect.md": "../../../payload/alias/../reference.md",
            "references": "../../../payload/references",
            "cross-cycle": "../../../payload/a",
            "outside": str(cls.outside),
            "outside-dir": str(cls.outside_dir),
            "dangling": "missing.md",
            "self": ".",
        }.items():
            (skill / name).symlink_to(target)
        shared = write(".agents/_smooth-devex-shared/templates/keep.md", "template\n").parent.parent
        (shared / "templates/reference.md").symlink_to("../../../payload/reference.md")
        (shared / "dangling").symlink_to("missing.md")
        (shared / "self").symlink_to(".")
        (shared / "outside-dir").symlink_to(cls.outside_dir)
        for tree in (skill, shared):
            for name in TEST_FILES:
                (tree / name).write_text("test\n")
            for name in TEST_DIRS:
                (tree / name).mkdir()
                (tree / name / "fixture.txt").write_text("test fixture\n")
        rules = cls.source / ".github/instructions/git"
        rules.mkdir(parents=True)
        (rules / "git-policy.instructions.md").symlink_to("../../../payload/rule.md")
        hooks = cls.source / ".agents/hooks"
        hooks.mkdir()
        (hooks / "worktask-skill-trigger.sh").symlink_to("../../payload/hook.sh")
        write(".agents/hooks/manage-rule-system-context.sh", "#!/bin/sh\nexit 0\n").chmod(0o755)
        subprocess.run(["git", "init", "-q", str(cls.source)], check=True)
        cls.commit_source(cls.source)

    @staticmethod
    def commit_source(source):
        subprocess.run(["git", "-C", str(source), "add", "-A"], check=True)
        subprocess.run(
            ["git", "-C", str(source), "-c", "user.name=Installer Test",
             "-c", "user.email=installer@example.invalid", "-c", "commit.gpgsign=false",
             "-c", "core.hooksPath=/dev/null", "commit", "-qm", "test: create payload fixture"],
            check=True,
        )

    def setUp(self):
        self.case = tempfile.TemporaryDirectory(dir=self.root)
        self.addCleanup(self.case.cleanup)
        self.case_root = Path(self.case.name)

    def copy_source(self, name):
        source = self.case_root / (name + "-source")
        shutil.copytree(self.source, source, symlinks=True)
        return source

    def prepare(self, port, name="case", global_install=False):
        consumer = self.case_root / port / name
        consumer.mkdir(parents=True)
        home = consumer / "home"
        home.mkdir()
        agent = consumer / ".agents"
        agent.mkdir()
        store = home / ".smooth-ai-devex" if global_install else agent / "_smooth-devex-shared"
        store.mkdir()
        manifest = store / "installation.json"
        manifest.write_text(json.dumps({"decisions_enabled": False, "skills": []}))
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(("SKILLS_", "SMOOTH_DEVEX_", "GIT_")) and key != "CDPATH"}
        env.update(HOME=str(home), TMPDIR=str(self.case_root), CODEX_HOME=str(home / ".codex"),
                   CLAUDE_HOME=str(home / ".claude"),
                   OPENCODE_CONFIG=str(home / ".config/opencode"), SMOOTH_DEVEX_HOME=str(store),
                   SKILLS_REPO=str(self.source), SKILLS_BRANCH="", SKILLS_ROOT="",
                   SKILLS_TEST_OWNED_EXTRA="alpha", CLONE_ROOT="/")
        return consumer, agent, store, manifest, env

    def run_installer(self, port, case, *flags, succeeds=True):
        launcher = ["bash", str(REPO / "scripts/install-skills.sh")]
        if port == "powershell":
            launcher = ["pwsh", "-NoLogo", "-NoProfile", "-NonInteractive", "-File",
                        str(REPO / "scripts/install-skills.ps1")]
        result = subprocess.run(launcher + list(flags), cwd=case[0], env=case[4],
                                capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        if succeeds:
            self.assertEqual(result.returncode, 0, output)
        else:
            self.assertNotEqual(result.returncode, 0, output)
        return output

    def assert_pruned(self, tree):
        for name in TEST_FILES + TEST_DIRS:
            self.assertFalse((tree / name).exists(), str(tree / name))

    def assert_payload(self, store):
        skill = store / "skills/alpha"
        self.assertEqual((skill / "reference.md").read_text(), "reference\n")
        self.assertFalse((skill / "reference.md").is_symlink())
        self.assertEqual((skill / "indirect.md").read_text(), "indirect reference\n")
        self.assertFalse((skill / "indirect.md").is_symlink())
        self.assertEqual((skill / "references/nested.md").read_text(), "nested\n")
        self.assertFalse((skill / "references").is_symlink())
        self.assertEqual((skill / "..hidden.md").read_text(), "hidden\n")
        self.assertTrue((skill / "scripts/main.py").is_file())
        self.assertFalse((skill / "scripts/test_nested.py").exists())
        self.assertFalse((skill / "AGENTS.md").exists())
        self.assert_pruned(skill)
        for name in ("outside", "outside-dir", "dangling", "self", "cross-cycle/next/next"):
            self.assertTrue((skill / name).is_symlink(), name)
        self.assertEqual(os.readlink(skill / "outside"), str(self.outside))
        self.assertEqual(self.outside.read_text(), "operator-owned\n")
        self.assertEqual((self.outside_dir / "test_main.py").read_text(), "operator test\n")
        rule = store / "rules/git/git-policy.instructions.md"
        self.assertTrue(rule.is_file())
        self.assertFalse(rule.is_symlink())
        hook = store / "hooks/worktask-skill-trigger.sh"
        self.assertTrue(hook.is_file())
        self.assertFalse(hook.is_symlink())
        self.assertTrue(os.access(hook, os.X_OK))

    def test_per_repo_payload_and_shared_refresh(self):
        for port in PORTS:
            with self.subTest(port=port):
                case = self.prepare(port)
                self.run_installer(port, case)
                self.assert_payload(case[1])
                self.assertFalse((case[0] / ".github").exists())
                shared = case[2]
                self.assert_pruned(shared)
                self.assertFalse((shared / "templates/reference.md").is_symlink())
                self.assertEqual((shared / "templates/reference.md").read_text(), "reference\n")
                (shared / "stale.txt").write_text("retired\n")
                (shared / "..stale.txt").write_text("retired\n")
                self.run_installer(port, case)
                self.assertFalse((shared / "stale.txt").exists())
                self.assertFalse((shared / "..stale.txt").exists())
                self.assertTrue((shared / "dangling").is_symlink())
                self.assertTrue((shared / "self").is_symlink())
                self.assertTrue((shared / "outside-dir").is_symlink())
                self.assertEqual((self.outside_dir / "test_main.py").read_text(), "operator test\n")
                self.assertEqual(json.loads(case[3].read_text())["skills"],
                                 [{"name": "alpha", "installed": True}])

    def test_global_payload(self):
        for port in PORTS:
            with self.subTest(port=port):
                case = self.prepare(port, global_install=True)
                self.run_installer(port, case, "-g")
                self.assert_payload(case[2])
                self.assertTrue((Path(case[4]["CODEX_HOME"]) / "skills/alpha").is_symlink())

    def test_global_ignores_inherited_claude_home(self):
        for port in PORTS:
            with self.subTest(port=port):
                operator_home = self.case_root / (port + "-operator-claude")
                operator_home.mkdir()
                (operator_home / "config.json").write_text("operator configuration\n")
                with patch.dict(os.environ, {"CLAUDE_HOME": str(operator_home)}):
                    case = self.prepare(port, global_install=True)
                expected = case[0] / "home/.claude"
                self.assertEqual(case[4].get("CLAUDE_HOME"), str(expected))
                expected.mkdir()
                self.run_installer(port, case, "-g")
                self.assertTrue((expected / "skills/alpha").is_symlink())
                self.assertEqual(sorted(path.name for path in operator_home.iterdir()), ["config.json"])
                self.assertEqual((operator_home / "config.json").read_text(), "operator configuration\n")

    def test_rules_write_through_dangling_operator_link(self):
        for port in PORTS:
            with self.subTest(port=port):
                case = self.prepare(port)
                (case[1] / "rules").symlink_to("../.github/instructions")
                self.run_installer(port, case, "-r")
                self.assertTrue((case[1] / "rules").is_symlink())
                self.assertTrue((case[0] / ".github/instructions/git/git-policy.instructions.md").is_file())
                self.assertFalse((case[1] / "skills").exists())

    def test_category_only_runs_do_not_create_skills(self):
        for port in PORTS:
            for flag in ("-r", "-h"):
                with self.subTest(port=port, flag=flag):
                    case = self.prepare(port, flag)
                    self.run_installer(port, case, flag)
                    self.assertFalse((case[1] / "skills").exists())
                    self.assertFalse((case[1] / ("hooks" if flag == "-r" else "rules")).exists())

    def test_missing_agent_root_is_refused(self):
        for port in PORTS:
            with self.subTest(port=port):
                case = self.prepare(port)
                shutil.rmtree(case[1])
                output = self.run_installer(port, case, succeeds=False)
                self.assertIn("no agent directory found", output)
                for name in (".agents", ".claude", ".codex"):
                    self.assertFalse((case[0] / name).exists())

    def test_disabled_skill_is_not_pruned_or_refreshed(self):
        for port in PORTS:
            for global_install in (False, True):
                with self.subTest(port=port, global_install=global_install):
                    case = self.prepare(port, str(global_install), global_install)
                    flags = ("-g", "-s") if global_install else ("-s",)
                    self.run_installer(port, case, *flags)
                    skill = (case[2] if global_install else case[1]) / "skills/alpha"
                    manifest = json.loads(case[3].read_text())
                    manifest["skills"][0]["installed"] = False
                    case[3].write_text(json.dumps(manifest))
                    (skill / "test_local.py").write_text("operator edit\n")
                    self.run_installer(port, case, *flags)
                    self.assertEqual((skill / "test_local.py").read_text(), "operator edit\n")

    def test_retained_skill_root_is_not_cleaned(self):
        for port in PORTS:
            for global_install in (False, True):
                with self.subTest(port=port, global_install=global_install):
                    name = str(global_install)
                    case = self.prepare(port, name, global_install)
                    external = case[0] / "external-skill"
                    (external / "tests").mkdir(parents=True)
                    expected = {
                        "SKILL.md": "# External skill\n",
                        "AGENTS.md": "operator context\n",
                        "test_main.py": "operator test\n",
                        "tests/fixture.txt": "operator fixture\n",
                        "runtime.py": "operator runtime\n",
                    }
                    for path, text in expected.items():
                        (external / path).write_text(text)
                    source = self.copy_source(port + name)
                    skill_source = source / ".agents/skills/alpha"
                    shutil.rmtree(skill_source)
                    skill_source.symlink_to(external, target_is_directory=True)
                    self.commit_source(source)
                    case[4]["SKILLS_REPO"] = str(source)
                    flags = ("-g", "-s") if global_install else ("-s",)
                    self.run_installer(port, case, *flags)
                    installed = (case[2] if global_install else case[1]) / "skills/alpha"
                    self.assertTrue(installed.is_symlink())
                    actual = {str(path.relative_to(external)): path.read_text()
                              for path in external.rglob("*") if path.is_file()}
                    self.assertEqual(actual, expected)

    def test_shared_root_must_be_materialized(self):
        for port in PORTS:
            for target in (".", "external", "missing"):
                with self.subTest(port=port, target=target):
                    case = self.prepare(port, target)
                    (case[1] / "operator-note.txt").write_text("operator note\n")
                    (case[1] / "AGENTS.md").write_text("operator context\n")
                    (case[1] / "test_local.py").write_text("operator test\n")
                    original_manifest = case[3].read_bytes()
                    external = case[0] / "external-shared"
                    external.mkdir()
                    (external / "test_external.py").write_text("external test\n")
                    source = self.copy_source(port + target)
                    shared_source = source / ".agents/_smooth-devex-shared"
                    shutil.rmtree(shared_source)
                    shared_source.symlink_to(external if target == "external" else target,
                                             target_is_directory=True)
                    self.commit_source(source)
                    case[4]["SKILLS_REPO"] = str(source)
                    output = self.run_installer(port, case, "-s", succeeds=False)
                    self.assertIn("shared payload root", output)
                    self.assertFalse(case[2].is_symlink())
                    self.assertEqual(case[3].read_bytes(), original_manifest)
                    self.assertEqual((case[1] / "operator-note.txt").read_text(), "operator note\n")
                    self.assertEqual((case[1] / "AGENTS.md").read_text(), "operator context\n")
                    self.assertEqual((case[1] / "test_local.py").read_text(), "operator test\n")
                    self.assertEqual((external / "test_external.py").read_text(), "external test\n")

    def test_shared_destination_root_link_is_refused(self):
        for port in PORTS:
            with self.subTest(port=port):
                case = self.prepare(port)
                original_manifest = case[3].read_bytes()
                external = case[0] / "external-shared"
                case[2].rename(external)
                (external / "test_external.py").write_text("external test\n")
                case[2].symlink_to(external, target_is_directory=True)
                output = self.run_installer(port, case, "-s", succeeds=False)
                self.assertIn("shared payload destination", output)
                self.assertTrue(case[2].is_symlink())
                self.assertEqual((external / "installation.json").read_bytes(), original_manifest)
                self.assertEqual((external / "test_external.py").read_text(), "external test\n")

    def test_shared_root_inside_clone_is_materialized(self):
        for port in PORTS:
            with self.subTest(port=port):
                case = self.prepare(port)
                source = self.copy_source(port)
                shared_source = source / ".agents/_smooth-devex-shared"
                shared_source.rename(source / "payload/shared")
                shared_source.symlink_to("../payload/shared", target_is_directory=True)
                self.commit_source(source)
                case[4]["SKILLS_REPO"] = str(source)
                self.run_installer(port, case, "-s")
                self.assertFalse(case[2].is_symlink())
                self.assertEqual((case[2] / "templates/keep.md").read_text(), "template\n")
                self.assertTrue(case[3].is_file())


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", choices=("bash", "powershell", "all"), default="bash")
    args, remaining = parser.parse_known_args()
    PORTS = ("bash", "powershell") if args.port == "all" else (args.port,)
    unittest.main(argv=[__file__] + remaining)
