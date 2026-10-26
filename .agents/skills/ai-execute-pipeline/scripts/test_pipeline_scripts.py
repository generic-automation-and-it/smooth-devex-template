#!/usr/bin/env python3
"""
Skill: ai-execute-pipeline
Script tests: each script runs for real against a throwaway git repo (with a local bare `origin`)
and a stub `gh` placed first on PATH. The stub never reaches GitHub; it answers from files in a
per-test directory and logs every call.

  python3 .agents/skills/ai-execute-pipeline/scripts/test_pipeline_scripts.py
"""
import json
import os
import shutil
import subprocess  # shell=False list calls only: the scripts under test are the subject
import tempfile
import textwrap
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent

STUB_GH = textwrap.dedent(r"""
    #!/usr/bin/env bash
    printf '%s\n' "$*" >> "$STUB/calls.log"
    case "$1 $2" in
      "auth status") exit "$(cat "$STUB/auth_rc" 2>/dev/null || echo 0)" ;;
      "stack --version") [[ -f "$STUB/stack_installed" ]] && exit 0 || exit 1 ;;
      "stack view")
        if [[ -f "$STUB/stack_view.json" ]]; then cat "$STUB/stack_view.json"; exit 0; fi
        echo "x current branch is not part of a stack" >&2; exit 2 ;;
      "stack init") git switch --quiet "$3" 2>/dev/null || git switch --quiet -c "$3" ;;
      "stack add") git switch --quiet -c "$3" ;;
      "stack submit") exit 0 ;;
      "pr view") cat "$STUB/pr_view.json" ;;
      "pr ready") exit 0 ;;
      "api "*) [[ -f "$STUB/reviews.json" ]] && cat "$STUB/reviews.json" || exit 1 ;;
      "repo view") echo '{"nameWithOwner":"o/r"}' ;;
      *) echo "stub gh: unhandled $*" >&2; exit 99 ;;
    esac
""").lstrip()


def git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


class ScriptTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.stub = self.tmp / "stub"
        self.stub.mkdir()
        bin_dir = self.tmp / "bin"
        bin_dir.mkdir()
        gh = bin_dir / "gh"
        gh.write_text(STUB_GH)
        gh.chmod(0o755)

        origin = self.tmp / "origin.git"
        subprocess.run(["git", "init", "--quiet", "--bare", "-b", "main", str(origin)], check=True)
        seed = self.tmp / "seed"
        subprocess.run(["git", "init", "--quiet", "-b", "main", str(seed)], check=True)
        self.identity(seed)
        (seed / "README.md").write_text("seed\n")
        git(seed, "add", ".")
        git(seed, "commit", "--quiet", "-m", "chore: seed")
        git(seed, "push", "--quiet", str(origin), "main")
        self.repo = self.tmp / "work"
        subprocess.run(["git", "clone", "--quiet", str(origin), str(self.repo)], check=True)
        self.identity(self.repo)
        self.worktask = self.tmp / "worktask.md"
        self.worktask.write_text("# Task: add paging\n")

        self.env = {
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "HOME": str(self.tmp / "home"),
            "STUB": str(self.stub),
            "GIT_CONFIG_GLOBAL": str(self.tmp / "gitconfig"),
            "GIT_CONFIG_NOSYSTEM": "1",
        }

    @staticmethod
    def identity(repo):
        git(repo, "config", "user.email", "t@example.com")
        git(repo, "config", "user.name", "t")

    def run_script(self, name, *args, **env):
        result = subprocess.run(
            [str(SCRIPTS / name), *args], cwd=self.repo, capture_output=True, text=True,
            env={**self.env, **env},
        )
        return result.returncode, result.stdout.strip(), result.stderr

    def json_of(self, name, *args, **env):
        code, out, err = self.run_script(name, *args, **env)
        self.assertEqual(code, 0, err)
        return json.loads(out)

    def stub_file(self, name, content):
        (self.stub / name).write_text(content if isinstance(content, str) else json.dumps(content))

    def calls(self):
        log = self.stub / "calls.log"
        return log.read_text().splitlines() if log.exists() else []

    def stack_view(self, current, *chain):
        branches, base = [], "main"
        for name in chain:
            branches.append({"name": name, "base": base, "isCurrent": name == current})
            base = name
        self.stub_file("stack_view.json", {"trunk": "main", "currentBranch": current, "branches": branches})


class PreflightTests(ScriptTestCase):
    def preflight(self, **env):
        base = {"AEP_WORKTASK": str(self.worktask), "AEP_PARENT": "164"}
        return self.run_script("preflight.sh", **{**base, **env})

    def test_missing_worktask_is_bad_input(self):
        code, _, err = self.preflight(AEP_WORKTASK="")
        self.assertEqual(code, 64)
        self.assertIn("--worktask is required", err)

    def test_missing_parent_is_bad_input(self):
        code, _, err = self.preflight(AEP_PARENT="")
        self.assertEqual(code, 64)
        self.assertIn("--parent is required", err)

    def test_bad_loops_is_bad_input(self):
        self.assertEqual(self.preflight(AEP_LOOPS="0")[0], 64)

    def test_dirty_tree_fails(self):
        (self.repo / "scratch.txt").write_text("x")
        code, _, err = self.preflight()
        self.assertEqual(code, 1)
        self.assertIn("not clean", err)

    def test_unauthenticated_gh_fails(self):
        self.stub_file("auth_rc", "1")
        code, _, err = self.preflight()
        self.assertEqual(code, 1)
        self.assertIn("not authenticated", err)

    def test_plain_mode_without_stack_extension(self):
        code, out, err = self.preflight()
        self.assertEqual(code, 0, err)
        state = json.loads(out)
        self.assertEqual((state["mode"], state["trunk"], state["expected_base"]), ("plain", "main", "main"))
        self.assertEqual(state["warnings"], [])

    def test_plain_mode_when_not_in_a_stack(self):
        self.stub_file("stack_installed", "")
        self.assertEqual(json.loads(self.preflight()[1])["mode"], "plain")

    def test_binding_flags_without_export_warn(self):
        state = json.loads(self.preflight(AEP_PRODUCT_NAME="imposter", AEP_EPIC_TICKET="160")[1])
        self.assertEqual(state["warnings"], [
            "--product-name has no effect without --understanding-export",
            "--epic-ticket has no effect without --understanding-export",
        ])

    def test_binding_flags_with_export_do_not_warn(self):
        state = json.loads(self.preflight(AEP_PRODUCT_NAME="imposter", AEP_UNDERSTANDING_EXPORT="true")[1])
        self.assertEqual(state["warnings"], [])

    def test_initialize_needs_the_stack_extension(self):
        code, _, err = self.preflight(AEP_INITIALIZE="true")
        self.assertEqual(code, 1)
        self.assertIn("gh stack extension", err)

    def test_initialize_starts_a_stack(self):
        self.stub_file("stack_installed", "")
        state = json.loads(self.preflight(AEP_INITIALIZE="true")[1])
        self.assertEqual((state["mode"], state["expected_base"]), ("stack-init", "main"))

    def test_initialize_inside_a_stack_fails(self):
        self.stub_file("stack_installed", "")
        self.stack_view("main", "feat/184-a")
        code, _, err = self.preflight(AEP_INITIALIZE="true")
        self.assertEqual(code, 1)
        self.assertIn("already in a stack", err)

    def test_stack_top_adds_a_layer_on_top(self):
        self.stub_file("stack_installed", "")
        git(self.repo, "switch", "--quiet", "-c", "feat/185-b")
        self.stack_view("feat/185-b", "feat/184-a", "feat/185-b")
        state = json.loads(self.preflight()[1])
        self.assertEqual((state["mode"], state["expected_base"]), ("stack-add", "feat/185-b"))

    def test_stack_member_that_is_not_the_top_fails(self):
        self.stub_file("stack_installed", "")
        git(self.repo, "switch", "--quiet", "-c", "feat/184-a")
        self.stack_view("feat/184-a", "feat/184-a", "feat/185-b")
        code, _, err = self.preflight()
        self.assertEqual(code, 1)
        self.assertIn("is not the stack top", err)


class BranchTests(ScriptTestCase):
    def branch(self, mode, **env):
        base = {"AEP_MODE": mode, "AEP_TRUNK": "main", "AEP_TYPE": "feat", "AEP_TICKET": "184", "AEP_SLUG": "add-paging"}
        return self.run_script("branch.sh", **{**base, **env})

    def test_plain_branches_from_origin_trunk_with_one_empty_commit(self):
        code, out, err = self.branch("plain")
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out), {"branch": "feat/184-add-paging", "empty_commit": True})
        self.assertEqual(git(self.repo, "rev-parse", "--abbrev-ref", "HEAD"), "feat/184-add-paging")
        self.assertEqual(git(self.repo, "log", "-1", "--format=%s"), "chore: start 184")
        self.assertEqual(git(self.repo, "diff", "--stat", "origin/main..HEAD"), "")

    def test_stack_init_uses_gh_stack_init_with_the_branch(self):
        state = json.loads(self.branch("stack-init")[1])
        self.assertTrue(state["empty_commit"])
        self.assertIn("stack init feat/184-add-paging", self.calls())

    def test_stack_init_works_when_trunk_is_checked_out_in_another_worktree(self):
        git(self.repo, "switch", "--quiet", "-c", "previous-work")
        git(self.repo, "worktree", "add", "--quiet", str(self.tmp / "main-checkout"), "main")
        code, out, err = self.branch("stack-init")
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out)["branch"], "feat/184-add-paging")
        self.assertEqual(git(self.repo, "merge-base", "HEAD", "origin/main"), git(self.repo, "rev-parse", "origin/main"))

    def test_stack_add_on_a_layer_with_commits_needs_no_empty_commit(self):
        git(self.repo, "switch", "--quiet", "-c", "feat/183-layer-one")
        (self.repo / "one.txt").write_text("1\n")
        git(self.repo, "add", ".")
        git(self.repo, "commit", "--quiet", "-m", "feat: layer one")
        head_before = git(self.repo, "rev-parse", "HEAD")
        state = json.loads(self.branch("stack-add")[1])
        self.assertEqual(state, {"branch": "feat/184-add-paging", "empty_commit": False})
        self.assertIn("stack add feat/184-add-paging", self.calls())
        self.assertEqual(git(self.repo, "rev-parse", "HEAD"), head_before)

    def test_jira_style_ticket_is_accepted(self):
        self.assertEqual(json.loads(self.branch("plain", AEP_TICKET="ABC-12")[1])["branch"], "feat/ABC-12-add-paging")

    def test_rerun_on_the_branch_does_not_recreate_it(self):
        self.branch("plain")
        code, out, _ = self.branch("plain")
        self.assertEqual((code, json.loads(out)["empty_commit"]), (0, False))

    def test_existing_branch_elsewhere_fails(self):
        git(self.repo, "branch", "feat/184-add-paging")
        self.assertEqual(self.branch("plain")[0], 1)

    def test_invalid_inputs_are_rejected(self):
        for env in ({"AEP_TYPE": "feature"}, {"AEP_SLUG": "Add Paging"}, {"AEP_SLUG": "a-b-c-d-e-f-g"},
                    {"AEP_TICKET": "184; rm"}, {"AEP_MODE": "stack"}):
            with self.subTest(env=env):
                self.assertEqual(self.branch(env.pop("AEP_MODE", "plain"), **env)[0], 64)
        self.assertEqual(self.calls(), [])


class StackTests(ScriptTestCase):
    def test_detect_off_stack_is_not_an_error(self):
        self.assertEqual(self.json_of("stack.sh", "detect"), {"in_stack": False})

    def test_detect_reports_the_top(self):
        self.stack_view("feat/184-a", "feat/184-a", "feat/185-b")
        state = self.json_of("stack.sh", "detect")
        self.assertEqual((state["in_stack"], state["top"], state["current"]), (True, "feat/185-b", "feat/184-a"))

    def test_detect_rejects_a_branching_stack(self):
        self.stub_file("stack_view.json", {"trunk": "main", "currentBranch": "a", "branches": [
            {"name": "a", "base": "main"}, {"name": "b", "base": "a"}, {"name": "c", "base": "a"}]})
        self.assertEqual(self.run_script("stack.sh", "detect")[0], 3)

    def test_submit_verifies_the_rewired_base(self):
        self.stub_file("pr_view.json", {"number": 7, "url": "u", "baseRefName": "feat/184-a", "isDraft": True})
        state = self.json_of("stack.sh", "submit", AEP_BRANCH="feat/185-b", AEP_EXPECTED_BASE="feat/184-a")
        self.assertEqual(state, {"pr": 7, "url": "u", "base": "feat/184-a", "draft": True})
        self.assertEqual([c for c in self.calls() if c.startswith("stack submit")], ["stack submit --auto"])

    def test_submit_fails_loudly_on_a_wrong_base(self):
        self.stub_file("pr_view.json", {"number": 7, "url": "u", "baseRefName": "main", "isDraft": True})
        code, _, err = self.run_script("stack.sh", "submit", AEP_BRANCH="feat/185-b", AEP_EXPECTED_BASE="feat/184-a")
        self.assertEqual(code, 4)
        self.assertIn("expected 'feat/184-a'", err)


class PrTests(ScriptTestCase):
    def pr_view(self, draft):
        self.stub_file("pr_view.json", {"number": 7, "url": "u", "isDraft": draft, "headRefOid": "abc", "baseRefName": "main"})

    def test_ready_marks_a_draft_ready(self):
        self.pr_view(True)
        self.run_script("pr.sh", "ready", AEP_PR="7")
        self.assertIn("pr ready 7", self.calls())

    def test_ready_is_a_noop_when_already_ready(self):
        self.pr_view(False)
        self.run_script("pr.sh", "ready", AEP_PR="7")
        self.assertNotIn("pr ready 7", self.calls())

    def test_rejects_a_non_ref(self):
        self.assertEqual(self.run_script("pr.sh", "view", AEP_PR="7; true")[0], 64)


class WaitForReviewTests(ScriptTestCase):
    HEAD = "1234567890abcdef1234567890abcdef12345678"

    def report(self, sha, critical, high, when="2026-10-26T10:00:00Z"):
        return {"id": int(when[11:13]), "submitted_at": when, "body": (
            f"## 🤖 OpenCode CLI Code Review - Commit: `{sha[:7]}`\n\n"
            f"- Count of 🔴 Critical Issues: {critical}\n- Count of 🟠 High Priority Issues: {high}\n")}

    def wait(self, *reviews, raw=None):
        self.stub_file("pr_view.json", {"headRefOid": self.HEAD})
        if raw is not None:
            self.stub_file("reviews.json", raw)
        elif reviews:
            self.stub_file("reviews.json", list(reviews))
        return self.run_script("wait-for-review.sh", AEP_PR="7", AEP_POLL_INTERVAL="0", AEP_POLL_TIMEOUT="0")

    def test_clean_report_for_head_exits_zero(self):
        code, out, _ = self.wait(self.report(self.HEAD, 0, 0))
        self.assertEqual((code, json.loads(out)["status"]), (0, "clean"))

    def test_critical_finding_exits_ten(self):
        code, out, _ = self.wait(self.report(self.HEAD, 2, 0))
        self.assertEqual((code, json.loads(out)["critical"]), (10, 2))

    def test_high_finding_exits_ten(self):
        self.assertEqual(self.wait(self.report(self.HEAD, 0, 1))[0], 10)

    def test_report_for_an_older_commit_is_ignored(self):
        code, out, _ = self.wait(self.report("fedcba9876543210", 3, 3))
        self.assertEqual((code, json.loads(out)["status"]), (2, "timeout"))

    def test_newest_head_report_wins(self):
        code, _, _ = self.wait(self.report(self.HEAD, 1, 0, "2026-10-26T09:00:00Z"),
                               self.report(self.HEAD, 0, 0, "2026-10-26T11:00:00Z"))
        self.assertEqual(code, 0)

    def test_other_reviews_are_ignored(self):
        code, _, _ = self.wait({"id": 1, "submitted_at": "2026-10-26T12:00:00Z", "body": "LGTM"},
                               self.report(self.HEAD, 0, 0))
        self.assertEqual(code, 0)

    def test_report_without_counts_is_unreadable(self):
        broken = {"id": 9, "submitted_at": "2026-10-26T10:00:00Z",
                  "body": f"## 🤖 OpenCode CLI Code Review - Commit: `{self.HEAD[:7]}`\n\nno counts"}
        self.assertEqual(self.wait(broken)[0], 3)

    def test_persistent_api_error_exits_three(self):
        code, out, _ = self.wait()
        self.assertEqual((code, json.loads(out)["status"]), (3, "error"))


class ResolveSkillTests(ScriptTestCase):
    def make_skill(self, root):
        root.mkdir(parents=True)
        (root / "SKILL.md").write_text("---\nname: x\n---\n")
        return str(root.resolve())

    def test_explicit_path_wins(self):
        explicit = self.make_skill(self.tmp / "custom" / "jira-ticket")
        self.make_skill(self.repo / ".agents" / "skills" / "jira-ticket")
        code, out, _ = self.run_script("resolve-skill.sh", AEP_SKILL_NAME="jira-ticket", AEP_SKILL_PATH=explicit)
        self.assertEqual((code, out), (0, explicit))

    def test_explicit_path_needs_no_skill_name(self):
        explicit = self.make_skill(self.tmp / "custom" / "JiraTicket")
        code, out, err = self.run_script("resolve-skill.sh", AEP_SKILL_PATH=explicit)
        self.assertEqual((code, out), (0, explicit), err)

    def test_vendored_context_install_is_found(self):
        vendored = self.make_skill(self.repo / ".context" / ".smooth-ai-review" / "skills" / "ai-review")
        self.assertEqual(self.run_script("resolve-skill.sh", AEP_SKILL_NAME="ai-review")[1], vendored)

    def test_home_install_is_found(self):
        home = self.make_skill(Path(self.env["HOME"]) / ".claude" / "skills" / "mimisbrunnr-kvasir-understanding")
        self.assertEqual(self.run_script("resolve-skill.sh", AEP_SKILL_NAME="mimisbrunnr-kvasir-understanding")[1], home)

    def test_missing_skill_and_bad_names(self):
        self.assertEqual(self.run_script("resolve-skill.sh", AEP_SKILL_NAME="nope")[0], 1)
        self.assertEqual(self.run_script("resolve-skill.sh", AEP_SKILL_NAME="../etc")[0], 64)
        self.assertEqual(self.run_script("resolve-skill.sh", AEP_SKILL_NAME="x", AEP_SKILL_PATH=str(self.tmp))[0], 1)


class ExportUnderstandingTests(ScriptTestCase):
    def kvasir(self):
        skill = self.tmp / "kvasir"
        (skill / "scripts").mkdir(parents=True)
        (skill / "scripts" / "understanding_client.py").write_text(textwrap.dedent(f"""
            import os, sys
            with open({str(self.stub / 'kvasir.log')!r}, "a") as log:
                log.write(" ".join(sys.argv[1:]) + "\\n")
            if sys.argv[1] == "dump":
                sys.stdin.read()
                os.makedirs(".context/dump-1", exist_ok=True)
                print("SESSION DUMP WRITTEN: .context/dump-1")
            else:
                print("export complete")
        """))
        return str(skill)

    def test_dump_then_export_with_bindings(self):
        result = subprocess.run(
            [str(SCRIPTS / "export-understanding.sh")], cwd=self.repo, input="- a durable claim\n",
            capture_output=True, text=True,
            env={**self.env, "AEP_KVASIR_DIR": self.kvasir(), "AEP_TICKETS": "github:164,github:184",
                 "AEP_INITIATIVE": "LLM-Optimization", "AEP_PRODUCT_NAME": "imposter"})
        self.assertEqual(result.returncode, 0, result.stderr)
        dump, export = (self.stub / "kvasir.log").read_text().splitlines()
        self.assertEqual(dump, "dump --currentsession --from - --tickets github:164,github:184 "
                               "--repository o/r --initiative LLM-Optimization")
        self.assertEqual(export, "export .context/dump-1 --tickets github:164,github:184 "
                                 "--repository o/r --initiative LLM-Optimization --product-name imposter")

    def test_bad_tickets_are_rejected(self):
        code, _, _ = self.run_script("export-understanding.sh", AEP_KVASIR_DIR=self.kvasir(), AEP_TICKETS="184")
        self.assertEqual(code, 64)


class ScriptHygieneTests(unittest.TestCase):
    def test_no_tracing_or_environment_dumps(self):
        for script in SCRIPTS.glob("*.sh"):
            text = script.read_text()
            with self.subTest(script=script.name):
                self.assertTrue(text.startswith("#!/usr/bin/env bash\n"))
                self.assertIn("set -euo pipefail", text)
                for banned in ("set -x", "printenv", "\nenv\n"):
                    self.assertNotIn(banned, text)
                self.assertTrue(os.access(script, os.X_OK))


if __name__ == "__main__":
    unittest.main()
