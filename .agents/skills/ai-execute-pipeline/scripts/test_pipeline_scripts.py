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
      "stack checkout") git switch --quiet "$3" ;;
      "stack submit") exit 0 ;;
      "pr view")
        if [[ -f "$STUB/pr_view_fail_once" ]]; then rm "$STUB/pr_view_fail_once"; exit 1; fi
        if [[ -f "$STUB/pr_$3.json" ]]; then cat "$STUB/pr_$3.json"; else cat "$STUB/pr_view.json"; fi ;;
      "pr ready") exit "$(cat "$STUB/pr_ready_rc" 2>/dev/null || echo 0)" ;;
      "api "*) [[ -f "$STUB/reviews.json" ]] && cat "$STUB/reviews.json" || exit 1 ;;
      "repo view") echo '{"nameWithOwner":"o/r"}' ;;
      "run view") [[ -f "$STUB/run_$3.log" ]] && cat "$STUB/run_$3.log" || exit 1 ;;
      *) echo "stub gh: unhandled $*" >&2; exit 99 ;;
    esac
""").lstrip()


def git(cwd, env, *args):
    return subprocess.run(["git", *args], cwd=cwd, env=env, check=True, capture_output=True, text=True).stdout.strip()


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
        gitconfig = self.tmp / "gitconfig"
        gitconfig.write_text("[user]\n\temail = t@example.com\n\tname = t\n[commit]\n\tgpgsign = false\n")
        self.env = {
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "HOME": str(self.tmp / "home"),
            "STUB": str(self.stub),
            "GIT_CONFIG_GLOBAL": str(gitconfig),
            "GIT_CONFIG_NOSYSTEM": "1",
        }

        origin = self.tmp / "origin.git"
        self.git(self.tmp, "init", "--quiet", "--bare", "-b", "main", str(origin))
        seed = self.tmp / "seed"
        self.git(self.tmp, "init", "--quiet", "-b", "main", str(seed))
        (seed / "README.md").write_text("seed\n")
        self.git(seed, "add", ".")
        self.git(seed, "commit", "--quiet", "-m", "chore: seed")
        self.git(seed, "push", "--quiet", str(origin), "main")
        self.repo = self.tmp / "work"
        self.git(self.tmp, "clone", "--quiet", str(origin), str(self.repo))
        self.worktask = self.tmp / "worktask.md"
        self.worktask.write_text("# Task: add paging\n")

    def git(self, cwd, *args):
        return git(cwd, self.env, *args)

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
        branches = [{"name": name, "base": f"{index:040x}", "isCurrent": name == current}
                    for index, name in enumerate(chain, start=1)]
        self.stub_file("stack_view.json", {"trunk": "main", "currentBranch": current, "branches": branches})

    def local_stacks(self, *chains):
        stacks = [{"trunk": {"branch": "main", "head": "0" * 40},
                   "branches": [{"branch": name, "base": "0" * 40} for name in chain]} for chain in chains]
        (self.repo / ".git" / "gh-stack").write_text(json.dumps({"schemaVersion": 1, "stacks": stacks}))


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
        self.assertEqual(state["stack"], {"available": False, "in_stack": False, "top": None, "layers": 0})
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
        self.git(self.repo, "switch", "--quiet", "-c", "feat/185-b")
        self.stack_view("feat/185-b", "feat/184-a", "feat/185-b")
        state = json.loads(self.preflight()[1])
        self.assertEqual((state["mode"], state["expected_base"]), ("stack-add", "feat/185-b"))

    def test_plain_run_reports_locally_tracked_stacks(self):
        self.stub_file("stack_installed", "")
        self.local_stacks(["feat/184-a", "feat/185-b"])
        state = json.loads(self.preflight()[1])
        self.assertEqual((state["mode"], state["stack"]["available"], state["stack"]["in_stack"]), ("plain", True, False))
        self.assertIn("feat/185-b", state["warnings"][0])
        self.assertIn("--stack <branch>", state["warnings"][0])

    def test_stack_and_initialize_together_are_bad_input(self):
        code, _, err = self.preflight(AEP_INITIALIZE="true", AEP_STACK="true")
        self.assertEqual(code, 64)
        self.assertIn("pass only one", err)

    def test_stack_value_must_be_a_branch_name(self):
        self.assertEqual(self.preflight(AEP_STACK="a..b")[0], 64)

    def test_stack_needs_the_stack_extension(self):
        code, _, err = self.preflight(AEP_STACK="true")
        self.assertEqual(code, 1)
        self.assertIn("gh stack extension", err)

    def test_bare_stack_off_stack_fails(self):
        self.stub_file("stack_installed", "")
        code, _, err = self.preflight(AEP_STACK="true")
        self.assertEqual(code, 1)
        self.assertIn("is not in a stack", err)

    def test_bare_stack_on_the_top_adds_a_layer(self):
        self.stub_file("stack_installed", "")
        self.git(self.repo, "switch", "--quiet", "-c", "feat/185-b")
        self.stack_view("feat/185-b", "feat/184-a", "feat/185-b")
        state = json.loads(self.preflight(AEP_STACK="true")[1])
        self.assertEqual((state["mode"], state["expected_base"]), ("stack-add", "feat/185-b"))
        self.assertEqual(state["stack"], {"available": True, "in_stack": True, "top": "feat/185-b", "layers": 2})

    def test_stack_branch_joins_a_stack_from_an_unrelated_branch(self):
        self.stub_file("stack_installed", "")
        self.git(self.repo, "switch", "--quiet", "-c", "workspace/placeholder")
        self.local_stacks(["feat/184-a", "feat/185-b"])
        state = json.loads(self.preflight(AEP_STACK="feat/184-a")[1])
        self.assertEqual((state["mode"], state["expected_base"]), ("stack-add", "feat/185-b"))
        self.assertEqual(state["stack"], {"available": True, "in_stack": True, "top": "feat/185-b", "layers": 2})

    def test_stack_branch_whose_top_is_checked_out_elsewhere_fails(self):
        self.stub_file("stack_installed", "")
        self.git(self.repo, "branch", "feat/185-b")
        self.git(self.repo, "worktree", "add", "--quiet", str(self.tmp / "other"), "feat/185-b")
        self.local_stacks(["feat/184-a", "feat/185-b"])
        code, _, err = self.preflight(AEP_STACK="feat/184-a")
        self.assertEqual(code, 1)
        self.assertIn("checked out in the worktree", err)
        self.assertIn("other", err)

    def test_stack_branch_not_in_a_local_stack_fails(self):
        self.stub_file("stack_installed", "")
        code, _, err = self.preflight(AEP_STACK="feat/999-x")
        self.assertEqual(code, 1)
        self.assertIn("not in a locally tracked stack", err)

    def commit_agent_settings(self, branch):
        self.git(self.repo, "switch", "--quiet", "-c", branch)
        (self.repo / ".agents").mkdir(exist_ok=True)
        (self.repo / ".agents" / "settings.json").write_text('{"local": true}\n')
        self.git(self.repo, "add", ".")
        self.git(self.repo, "commit", "--quiet", "-m", "chore(agents): local settings")

    def test_switch_that_rewrites_agent_config_fails_before_anything_is_created(self):
        self.commit_agent_settings("generik0/settings")
        code, _, err = self.preflight()
        self.assertEqual(code, 1)
        self.assertIn("rewrites agent config (.agents/settings.json)", err)
        self.assertNotIn("stack init", " ".join(self.calls()))

    def test_switch_with_unchanged_agent_config_passes(self):
        self.git(self.repo, "switch", "--quiet", "-c", "generik0/other")
        (self.repo / "notes.txt").write_text("x\n")
        self.git(self.repo, "add", ".")
        self.git(self.repo, "commit", "--quiet", "-m", "docs: notes")
        self.assertEqual(json.loads(self.preflight()[1])["mode"], "plain")

    def test_adding_a_layer_on_the_current_top_does_not_switch(self):
        self.stub_file("stack_installed", "")
        self.commit_agent_settings("feat/185-b")
        self.stack_view("feat/185-b", "feat/185-b")
        self.assertEqual(json.loads(self.preflight()[1])["mode"], "stack-add")

    def test_resume_on_its_branch_allows_a_dirty_tree_and_no_switch(self):
        self.commit_agent_settings("feat/184-a")
        (self.repo / "half-done.txt").write_text("x")
        code, out, err = self.preflight(AEP_RESUME_BRANCH="feat/184-a")
        self.assertEqual(code, 0, err)
        state = json.loads(out)
        self.assertEqual((state["mode"], state["expected_base"], state["resume"]), ("plain", "main", True))

    def test_resume_on_another_branch_fails(self):
        code, _, err = self.preflight(AEP_RESUME_BRANCH="feat/184-a")
        self.assertEqual(code, 1)
        self.assertIn("resuming needs 'feat/184-a' checked out", err)

    def test_resume_of_a_stacked_layer_expects_the_layer_below(self):
        self.stub_file("stack_installed", "")
        self.git(self.repo, "switch", "--quiet", "-c", "feat/185-b")
        self.stack_view("feat/185-b", "feat/184-a", "feat/185-b")
        state = json.loads(self.preflight(AEP_RESUME_BRANCH="feat/185-b")[1])
        self.assertEqual((state["mode"], state["expected_base"]), ("stack-add", "feat/184-a"))

    def test_resume_of_stack_layer_one_expects_trunk(self):
        self.stub_file("stack_installed", "")
        self.git(self.repo, "switch", "--quiet", "-c", "feat/184-a")
        self.stack_view("feat/184-a", "feat/184-a", "feat/185-b")
        state = json.loads(self.preflight(AEP_RESUME_BRANCH="feat/184-a")[1])
        self.assertEqual((state["mode"], state["expected_base"]), ("stack-init", "main"))

    def test_stack_member_that_is_not_the_top_fails(self):
        self.stub_file("stack_installed", "")
        self.git(self.repo, "switch", "--quiet", "-c", "feat/184-a")
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
        self.assertEqual(self.git(self.repo, "rev-parse", "--abbrev-ref", "HEAD"), "feat/184-add-paging")
        self.assertEqual(self.git(self.repo, "log", "-1", "--format=%s"), "chore: start 184")
        self.assertEqual(self.git(self.repo, "diff", "--stat", "origin/main..HEAD"), "")

    def test_stack_init_uses_gh_stack_init_with_the_branch(self):
        state = json.loads(self.branch("stack-init")[1])
        self.assertTrue(state["empty_commit"])
        self.assertIn("stack init feat/184-add-paging", self.calls())

    def test_stack_init_works_when_trunk_is_checked_out_in_another_worktree(self):
        self.git(self.repo, "switch", "--quiet", "-c", "previous-work")
        self.git(self.repo, "worktree", "add", "--quiet", str(self.tmp / "main-checkout"), "main")
        code, out, err = self.branch("stack-init")
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out)["branch"], "feat/184-add-paging")
        self.assertEqual(self.git(self.repo, "merge-base", "HEAD", "origin/main"), self.git(self.repo, "rev-parse", "origin/main"))

    def test_stack_add_on_a_layer_with_commits_needs_no_empty_commit(self):
        self.git(self.repo, "switch", "--quiet", "-c", "feat/183-layer-one")
        (self.repo / "one.txt").write_text("1\n")
        self.git(self.repo, "add", ".")
        self.git(self.repo, "commit", "--quiet", "-m", "feat: layer one")
        head_before = self.git(self.repo, "rev-parse", "HEAD")
        state = json.loads(self.branch("stack-add")[1])
        self.assertEqual(state, {"branch": "feat/184-add-paging", "empty_commit": False})
        self.assertIn("stack add feat/184-add-paging", self.calls())
        self.assertEqual(self.git(self.repo, "rev-parse", "HEAD"), head_before)

    def test_stack_add_checks_out_the_base_layer_first(self):
        self.git(self.repo, "branch", "feat/183-layer-one")
        self.git(self.repo, "switch", "--quiet", "-c", "workspace/placeholder")
        code, out, err = self.branch("stack-add", AEP_BASE="feat/183-layer-one")
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out)["branch"], "feat/184-add-paging")
        stack_calls = [c for c in self.calls() if c.startswith("stack ")]
        self.assertEqual(stack_calls, ["stack checkout feat/183-layer-one", "stack add feat/184-add-paging"])

    def test_jira_style_ticket_is_accepted(self):
        self.assertEqual(json.loads(self.branch("plain", AEP_TICKET="ABC-12")[1])["branch"], "feat/ABC-12-add-paging")

    def test_rerun_on_the_branch_does_not_recreate_it(self):
        self.branch("plain")
        code, out, _ = self.branch("plain")
        self.assertEqual((code, json.loads(out)["empty_commit"]), (0, False))

    def test_existing_branch_elsewhere_fails(self):
        self.git(self.repo, "branch", "feat/184-add-paging")
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

    def test_detect_top_of_three_layers_with_sha_bases(self):
        self.stack_view("feat/185-b", "feat/184-a", "feat/185-b", "feat/186-c")
        state = self.json_of("stack.sh", "detect")
        self.assertEqual((state["top"], state["layers"], state["below"]), ("feat/186-c", 3, "feat/184-a"))

    def test_list_without_state_is_empty(self):
        self.assertEqual(self.json_of("stack.sh", "list"), [])

    def test_list_reads_every_local_stack(self):
        self.local_stacks(["feat/184-a", "feat/185-b"], ["fix/190-c"])
        self.assertEqual([(s["top"], s["layers"]) for s in self.json_of("stack.sh", "list")],
                         [("feat/185-b", 2), ("fix/190-c", 1)])

    def test_detect_rejects_an_empty_stack(self):
        self.stub_file("stack_view.json", {"trunk": "main", "currentBranch": "a", "branches": []})
        self.assertEqual(self.run_script("stack.sh", "detect")[0], 3)

    def test_submit_verifies_the_rewired_base(self):
        self.stack_view("feat/185-b", "feat/184-a", "feat/185-b")
        self.stub_file("pr_view.json", {"number": 7, "url": "u", "baseRefName": "feat/184-a", "isDraft": True})
        state = self.json_of("stack.sh", "submit", AEP_BRANCH="feat/185-b", AEP_EXPECTED_BASE="feat/184-a")
        self.assertEqual(state, {"pr": 7, "url": "u", "base": "feat/184-a", "draft": True})
        self.assertEqual([c for c in self.calls() if c.startswith("stack submit")], ["stack submit --auto"])

    def test_submit_refuses_when_a_layer_has_remote_only_commits(self):
        self.git(self.repo, "switch", "--quiet", "-c", "feat/184-a")
        self.git(self.repo, "commit", "--quiet", "--allow-empty", "-m", "feat: a")
        self.git(self.repo, "commit", "--quiet", "--allow-empty", "-m", "fix: collaborator")
        self.git(self.repo, "push", "--quiet", "origin", "feat/184-a")
        self.git(self.repo, "reset", "--quiet", "--hard", "HEAD~1")
        self.stack_view("feat/184-a", "feat/184-a")
        code, _, err = self.run_script("stack.sh", "submit", AEP_BRANCH="feat/184-a", AEP_EXPECTED_BASE="main")
        self.assertEqual(code, 5)
        self.assertIn("origin/feat/184-a has 1 commit(s)", err)
        self.assertNotIn("stack submit --auto", self.calls())

    def test_submit_fails_loudly_on_a_wrong_base(self):
        self.stack_view("feat/185-b", "feat/184-a", "feat/185-b")
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

    def test_ready_fails_when_the_first_lookup_fails(self):
        self.pr_view(True)
        self.stub_file("pr_view_fail_once", "")
        code, _, _ = self.run_script("pr.sh", "ready", AEP_PR="7")
        self.assertNotEqual(code, 0)
        self.assertNotIn("pr ready 7", self.calls())

    def test_rejects_a_non_ref(self):
        self.assertEqual(self.run_script("pr.sh", "view", AEP_PR="7; true")[0], 64)

    def run_row(self, name, status="COMPLETED", conclusion="SUCCESS", workflow="CI", run=101):
        return {"__typename": "CheckRun", "name": name, "workflowName": workflow, "status": status,
                "conclusion": conclusion, "detailsUrl": f"https://github.com/o/r/actions/runs/{run}/job/9"}

    def checks(self, *rows):
        self.stub_file("pr_view.json", {"headRefOid": "abc", "statusCheckRollup": list(rows)})
        code, out, err = self.run_script("pr.sh", "checks", AEP_PR="7")
        return code, json.loads(out) if out else None, err

    def test_checks_pass_with_skipped_cancelled_and_running_jobs(self):
        code, report, _ = self.checks(self.run_row("build"), self.run_row("e2e", conclusion="SKIPPED"),
                                      self.run_row("old", conclusion="CANCELLED"),
                                      self.run_row("test", status="IN_PROGRESS", conclusion=None))
        self.assertEqual(code, 0)
        self.assertEqual((report["failed"], report["passed"]), ([], 3))
        self.assertEqual(report["pending"], [{"name": "test", "workflow": "CI", "status": "IN_PROGRESS"}])

    def test_failed_and_timed_out_jobs_and_failed_statuses_exit_ten(self):
        code, report, _ = self.checks(
            self.run_row("DotNet Test", conclusion="FAILURE", workflow="api - [CI]", run=40524354785),
            self.run_row("slow", conclusion="TIMED_OUT", run=202),
            {"__typename": "StatusContext", "context": "sonar", "state": "ERROR", "targetUrl": "https://sonar/x"})
        self.assertEqual(code, 10)
        self.assertEqual([(f["name"], f["conclusion"], f["run_id"]) for f in report["failed"]],
                         [("DotNet Test", "FAILURE", 40524354785), ("slow", "TIMED_OUT", 202), ("sonar", "ERROR", None)])

    def test_the_ai_review_is_not_counted_as_another_check(self):
        code, report, _ = self.checks(
            self.run_row("LEGO PR Review", conclusion="FAILURE", workflow="OpenCode Review Report"),
            self.run_row("review / open-code-review-report", status="QUEUED", conclusion=None, workflow="PR Code Review Report"))
        self.assertEqual((code, report["failed"], report["pending"], report["passed"]), (0, [], [], 0))

    def test_failed_logs_are_written_to_files(self):
        self.stub_file("run_101.log", "step\nerror CS1002: ; expected\n")
        code, out, err = self.run_script("pr.sh", "failed-logs", AEP_RUN_IDS="101")
        self.assertEqual(code, 0, err)
        path = Path(json.loads(out)["logs"][0]["path"])
        self.assertEqual(path, (self.repo / ".context" / "ai-execute-pipeline" / "ci" / "101.log").resolve())
        self.assertIn("CS1002", path.read_text())

    def test_unreadable_log_exits_three_and_keeps_the_readable_ones(self):
        self.stub_file("run_101.log", "boom\n")
        code, out, err = self.run_script("pr.sh", "failed-logs", AEP_RUN_IDS="101,202")
        self.assertEqual(code, 3)
        self.assertEqual([log["run_id"] for log in json.loads(out)["logs"]], [101])
        self.assertIn("run 202", err)

    def test_failed_logs_reject_bad_run_ids(self):
        for ids in ("", "12;rm", "0", "1,,2"):
            with self.subTest(ids=ids):
                self.assertEqual(self.run_script("pr.sh", "failed-logs", AEP_RUN_IDS=ids)[0], 64)


class WaitForReviewTests(ScriptTestCase):
    HEAD = "1234567890abcdef1234567890abcdef12345678"

    def report(self, sha, critical, high, when="2026-10-26T10:00:00Z", user="github-actions[bot]"):
        return {"id": int(when[11:13]), "submitted_at": when, "user": {"login": user}, "commit_id": sha, "body": (
            f"## 🤖 OpenCode CLI Code Review - Commit: `{sha[:7]}`\n\n"
            f"- Count of 🔴 Critical Issues: {critical}\n- Count of 🟠 High Priority Issues: {high}\n")}

    def wait(self, *reviews, raw=None, checks=None, **env):
        self.stub_file("pr_view.json", {"headRefOid": self.HEAD, "statusCheckRollup": checks or []})
        if raw is not None:
            self.stub_file("reviews.json", raw)
        elif reviews:
            self.stub_file("reviews.json", list(reviews))
        return self.run_script("wait-for-review.sh", **{"AEP_PR": "7", "AEP_POLL_INTERVAL": "0", "AEP_POLL_TIMEOUT": "0", **env})

    def check(self, status, conclusion="", name="review / open-code-review-report", workflow="PR Code Review Report"):
        return {"__typename": "CheckRun", "name": name, "workflowName": workflow, "status": status, "conclusion": conclusion}

    def toggles(self):
        return [c for c in self.calls() if c.startswith("pr ready")]

    def test_review_not_started_toggles_draft_and_ready_once(self):
        code, out, _ = self.wait(self.report("fedcba9876543210", 0, 0), AEP_START_GRACE="0")
        self.assertEqual((code, json.loads(out)), (2, {"status": "timeout", "head": self.HEAD, "retriggered": True}))
        self.assertEqual(self.toggles(), ["pr ready 7 --undo", "pr ready 7"])

    def test_skipped_or_cancelled_review_run_is_not_started(self):
        self.wait(self.report("fedcba9876543210", 0, 0), AEP_START_GRACE="0",
                  checks=[self.check("COMPLETED", "SKIPPED"), self.check("COMPLETED", "CANCELLED"),
                          self.check("IN_PROGRESS", name="build", workflow="CI")])
        self.assertEqual(self.toggles(), ["pr ready 7 --undo", "pr ready 7"])

    def test_running_review_is_not_retriggered(self):
        code, out, _ = self.wait(self.report("fedcba9876543210", 0, 0), AEP_START_GRACE="0",
                                 checks=[self.check("COMPLETED", "CANCELLED"), self.check("IN_PROGRESS")])
        self.assertEqual((code, json.loads(out)["retriggered"]), (2, False))
        self.assertEqual(self.toggles(), [])

    def test_review_check_named_differently_is_found_by_its_workflow(self):
        self.wait(self.report("fedcba9876543210", 0, 0), AEP_START_GRACE="0",
                  checks=[self.check("IN_PROGRESS", name="LEGO PR Review", workflow="OpenCode Review Report")])
        self.assertEqual(self.toggles(), [])

    def test_review_check_name_alone_is_found(self):
        self.wait(self.report("fedcba9876543210", 0, 0), AEP_START_GRACE="0",
                  checks=[self.check("QUEUED", name="open-code-review-report", workflow="")])
        self.assertEqual(self.toggles(), [])

    def test_other_running_workflows_do_not_count_as_the_review(self):
        self.wait(self.report("fedcba9876543210", 0, 0), AEP_START_GRACE="0",
                  checks=[self.check("IN_PROGRESS", name="DotNet Test", workflow="recipe-editor-api - [CI]")])
        self.assertEqual(self.toggles(), ["pr ready 7 --undo", "pr ready 7"])

    def test_review_is_retriggered_at_most_once_per_wait(self):
        self.wait(self.report("fedcba9876543210", 0, 0), AEP_START_GRACE="0", AEP_POLL_TIMEOUT="1")
        self.assertEqual(self.toggles(), ["pr ready 7 --undo", "pr ready 7"])

    def test_no_started_check_before_the_grace(self):
        self.wait(self.report("fedcba9876543210", 0, 0))
        self.assertEqual(self.toggles(), [])

    def test_head_report_needs_no_started_check(self):
        code, out, _ = self.wait(self.report(self.HEAD, 0, 0), AEP_START_GRACE="0")
        self.assertEqual((code, json.loads(out)["retriggered"]), (0, False))
        self.assertEqual(self.toggles(), [])

    def test_failed_retrigger_exits_three(self):
        self.stub_file("pr_ready_rc", "1")
        code, out, err = self.wait(self.report("fedcba9876543210", 0, 0), AEP_START_GRACE="0")
        self.assertEqual((code, json.loads(out)["status"]), (3, "error"))
        self.assertIn("could not convert PR #7 to draft", err)

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

    def test_spoofed_report_from_another_reviewer_is_ignored(self):
        code, _, _ = self.wait(self.report(self.HEAD, 2, 0, "2026-10-26T09:00:00Z"),
                               self.report(self.HEAD, 0, 0, "2026-10-26T11:00:00Z", user="someone"))
        self.assertEqual(code, 10)

    def test_other_reviews_are_ignored(self):
        code, _, _ = self.wait({"id": 1, "submitted_at": "2026-10-26T12:00:00Z", "body": "LGTM"},
                               self.report(self.HEAD, 0, 0))
        self.assertEqual(code, 0)

    def test_changes_requested_without_critical_or_high_is_not_clean(self):
        code, out, _ = self.wait({**self.report(self.HEAD, 0, 0), "state": "CHANGES_REQUESTED"})
        self.assertEqual((code, json.loads(out)["status"]), (3, "blocked"))

    def test_report_without_counts_is_unreadable(self):
        broken = {**self.report(self.HEAD, 0, 0),
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


WORKTASK = "# Task: {title}\n\nProcess: link\n\n## Execution Profile\n- **Path:** Full\n\n## Instructions\n"


class QueueTests(ScriptTestCase):
    def setUp(self):
        super().setUp()
        self.folder = self.tmp / "GPA-602"
        self.folder.mkdir()
        (self.folder / "00-execution-plan.md").write_text("# Plan\n")
        for name in ("WT-01-a.md", "WT-02-b.md", "add-paging.md"):
            (self.folder / name).write_text(WORKTASK.format(title=name))

    def queue(self, *entries):
        path = self.tmp / "queue.json"
        path.write_text(json.dumps({"plan": "00-execution-plan.md", "entries": list(entries)}))
        return str(path)

    def entry(self, name, action="run", depends_on=(), gates=()):
        return {"worktask": name, "action": action, "depends_on": list(depends_on),
                "gates": [{"pr": pr} for pr in gates], "reason": "r"}

    def valid(self):
        return self.queue(self.entry("WT-02-b.md", "done"), self.entry("WT-01-a.md", gates=[430]),
                          self.entry("add-paging.md", depends_on=["WT-01-a.md"]))

    def queue_cmd(self, cmd, queue=None, **env):
        return self.run_script("queue.sh", cmd, AEP_WORKTASKS=str(self.folder), AEP_QUEUE=queue or "", **env)

    def test_discover_finds_the_plan_and_create_worktask_files_by_shape(self):
        (self.folder / "notes.md").write_text("# Notes\n")
        state = self.json_of("queue.sh", "discover", AEP_WORKTASKS=str(self.folder))
        self.assertTrue(state["plan"].endswith("00-execution-plan.md"))
        self.assertEqual([Path(w).name for w in state["worktasks"]], ["WT-01-a.md", "WT-02-b.md", "add-paging.md"])
        self.assertEqual(len(state["warnings"]), 1)
        self.assertIn("notes.md", state["warnings"][0])

    def test_discover_needs_exactly_one_plan(self):
        (self.folder / "00-execution-plan.md").unlink()
        self.assertEqual(self.run_script("queue.sh", "discover", AEP_WORKTASKS=str(self.folder))[0], 64)
        (self.folder / "a-plan.md").write_text("x")
        (self.folder / "B-PLAN.md").write_text("x")
        code, _, err = self.run_script("queue.sh", "discover", AEP_WORKTASKS=str(self.folder))
        self.assertEqual(code, 64)
        self.assertIn("found 2", err)

    def test_valid_queue_counts_actions(self):
        code, out, err = self.queue_cmd("validate", self.valid())
        self.assertEqual((code, json.loads(out)), (0, {"entries": 3, "run": 2, "done": 1, "human": 0}), err)

    def test_invalid_queues_are_refused_with_every_reason(self):
        cases = {
            "missing from the queue": [self.entry("WT-01-a.md"), self.entry("WT-02-b.md")],
            "appears 2 times": [self.entry("WT-01-a.md"), self.entry("WT-01-a.md"), self.entry("WT-02-b.md"),
                                self.entry("add-paging.md")],
            "is queued before its dependency": [self.entry("WT-01-a.md", depends_on=["WT-02-b.md"]),
                                                self.entry("WT-02-b.md"), self.entry("add-paging.md")],
            "depends on unknown": [self.entry("WT-01-a.md", depends_on=["nope.md"]), self.entry("WT-02-b.md"),
                                   self.entry("add-paging.md")],
            "depends on human-led": [self.entry("WT-02-b.md", "human"), self.entry("WT-01-a.md", depends_on=["WT-02-b.md"]),
                                     self.entry("add-paging.md")],
            "action must be": [self.entry("WT-01-a.md", "skip"), self.entry("WT-02-b.md"), self.entry("add-paging.md")],
            "gate pr must be": [self.entry("WT-01-a.md", gates=["430"]), self.entry("WT-02-b.md"), self.entry("add-paging.md")],
            "not a worktask in the folder": [self.entry("WT-01-a.md"), self.entry("WT-02-b.md"), self.entry("add-paging.md"),
                                             self.entry("other.md")],
        }
        for reason, entries in cases.items():
            with self.subTest(reason=reason):
                code, _, err = self.queue_cmd("validate", self.queue(*entries))
                self.assertEqual(code, 1)
                self.assertIn(reason, err)

    def test_next_skips_done_run_entries_and_ignores_done_and_human_actions(self):
        queue = self.valid()
        self.assertEqual(json.loads(self.queue_cmd("next", queue)[1])["worktask"], "WT-01-a.md")
        self.run_script("state.sh", "set", AEP_WORKTASK="WT-01-a.md", AEP_STATUS="done")
        state = json.loads(self.queue_cmd("next", queue)[1])
        self.assertEqual((state["worktask"], state["index"], state["remaining"]), ("add-paging.md", 2, 1))
        self.run_script("state.sh", "set", AEP_WORKTASK="add-paging.md", AEP_STATUS="done")
        self.assertEqual(json.loads(self.queue_cmd("next", queue)[1]), {"worktask": None, "remaining": 0})

    def test_gates_pass_only_when_every_pr_is_merged(self):
        self.stub_file("pr_430.json", {"state": "MERGED"})
        code, out, _ = self.queue_cmd("gates", self.valid(), AEP_WORKTASK="WT-01-a.md")
        self.assertEqual((code, json.loads(out)), (0, {"gates": [{"pr": 430, "state": "MERGED"}]}))
        self.stub_file("pr_430.json", {"state": "OPEN"})
        code, _, err = self.queue_cmd("gates", self.valid(), AEP_WORKTASK="WT-01-a.md")
        self.assertEqual(code, 4)
        self.assertIn("waits for PR #430", err)

    def test_entry_without_gates_passes(self):
        code, out, _ = self.queue_cmd("gates", self.valid(), AEP_WORKTASK="add-paging.md")
        self.assertEqual((code, json.loads(out)), (0, {"gates": []}))


class StateTests(ScriptTestCase):
    def state(self, cmd, **env):
        return self.run_script("state.sh", cmd, **{"AEP_WORKTASK": ".context/GPA-602/WT-01-a.md", **env})

    def test_unknown_worktask_has_empty_state(self):
        self.assertEqual(json.loads(self.state("get")[1]), {})

    def test_set_merges_fields_and_get_reads_them_back(self):
        self.state("set", AEP_TICKET="GPA-690", AEP_TICKET_URL="https://jira.example/browse/GPA-690", AEP_STEP="3",
                   AEP_STATUS="in-progress")
        self.state("set", AEP_BRANCH="fix/GPA-690-a", AEP_PR="434", AEP_STEP="5")
        self.assertEqual(json.loads(self.state("get")[1]), {
            "ticket": "GPA-690", "ticket_url": "https://jira.example/browse/GPA-690", "status": "in-progress",
            "step": 5, "branch": "fix/GPA-690-a", "pr": 434})
        stored = self.repo / ".context" / "ai-execute-pipeline" / "WT-01-a" / "state.json"
        self.assertTrue(stored.is_file())
        self.assertEqual(list(stored.parent.glob(".state.*")), [])

    def test_invalid_values_are_refused_and_nothing_is_written(self):
        for env in ({"AEP_TICKET": "GPA 690"}, {"AEP_TICKET_URL": "http://x"}, {"AEP_BRANCH": "a..b"},
                    {"AEP_PR": "0"}, {"AEP_STEP": "15"}, {"AEP_STATUS": "finished"}):
            with self.subTest(env=env):
                self.assertEqual(self.state("set", **env)[0], 64)
        self.assertFalse((self.repo / ".context").exists())

    def test_corrupt_state_is_reported(self):
        stored = self.repo / ".context" / "ai-execute-pipeline" / "WT-01-a"
        stored.mkdir(parents=True)
        (stored / "state.json").write_text("[]")
        self.assertEqual(self.state("get")[0], 1)


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
