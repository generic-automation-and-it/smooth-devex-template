#!/usr/bin/env python3
"""L1 contract tests for ai-ralph-loop decision evaluation (#138).

Stdlib `unittest` only. Run directly by file path:

  python3 -B .agents/skills/ai-ralph-loop/decisions/tests/test_decision_evaluate.py -v

Each test drives the real Bash CLI against a loopback HTTP stub, so the assertions are on
observable requests, stdout, stderr and audit files — not on the embedded module's private
structure. The stub replies from a bounded list; no sleeps and no external service.
"""
import json
import os
import shutil
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parents[2]
SCRIPT = SKILL_DIR / "decisions" / "scripts" / "decision-evaluate.sh"
PLAN_TEMPLATE = SKILL_DIR / "decisions" / "templates" / "plan.json"
BUILD_TEMPLATE = SKILL_DIR / "decisions" / "templates" / "build.json"
MODEL = "stub-model"
TIMEOUT = "5"


def template_questions(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))["questions"]


def choice_answer(choice, criteria, confidence=0.5):
    if len(criteria) == 1:
        probabilities = {choice: 1.0}
    else:
        others = (1.0 - 0.7) / (len(criteria) - 1)
        probabilities = {key: (0.7 if key == choice else others) for key in criteria}
    return {
        "type": "choice",
        "choice": choice,
        "probabilities": probabilities,
        "confidence": confidence,
    }


def score_answer(score=1.0, confidence=0.5, positive=0.0, high=0.0):
    remaining = max(0.0, 1.0 - positive - high)
    return {
        "type": "score",
        "score": score,
        "legend": {
            "0": "harmful — ignores the criteria",
            "1": "neutral — ignores the criteria",
            "2": "positive — ignores the criteria",
            "3": "high — ignores the criteria",
        },
        "probabilities": {
            "0": remaining / 2.0,
            "1": remaining / 2.0,
            "2": positive,
            "3": high,
        },
        "confidence": confidence,
    }


def plan_response(
    coverage="nice_to_have",
    change="success",
    necessity="beneficial",
    positive=0.0,
    high=0.0,
    confidence=0.5,
    score=1.0,
):
    questions = template_questions(PLAN_TEMPLATE)
    return {
        "model": MODEL,
        "answers": {
            "change_assessment": choice_answer(change, questions["change_assessment"]["criteria"]),
            "requirement_coverage": choice_answer(coverage, questions["requirement_coverage"]["criteria"]),
            "design_necessity": choice_answer(necessity, questions["design_necessity"]["criteria"]),
            "architectural_value": score_answer(
                score=score, confidence=confidence, positive=positive, high=high
            ),
        },
        "usage": {"input_tokens": 1, "output_tokens": 0},
    }


def code_response(
    change="success",
    developer="closes_gap",
    necessity="essential",
    primary="correctness",
    closes=0.3,
    improves=0.3,
    confidence=0.5,
):
    questions = template_questions(BUILD_TEMPLATE)
    developer_criteria = questions["developer_value"]["criteria"]
    other_keys = [
        key for key in developer_criteria if key not in ("closes_gap", "improves_quality")
    ]
    remaining = max(0.0, 1.0 - closes - improves)
    share = remaining / len(other_keys) if other_keys else 0.0
    developer_answer = {
        "type": "choice",
        "choice": developer,
        "probabilities": {
            "closes_gap": closes,
            "improves_quality": improves,
            **{key: share for key in other_keys},
        },
        "confidence": confidence,
    }
    return {
        "model": MODEL,
        "answers": {
            "change_assessment": choice_answer(change, questions["change_assessment"]["criteria"]),
            "developer_value": developer_answer,
            "necessity": choice_answer(necessity, questions["necessity"]["criteria"]),
            "primary_value_category": choice_answer(
                primary, questions["primary_value_category"]["criteria"]
            ),
        },
        "usage": {"input_tokens": 1, "output_tokens": 0},
    }


class StubHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length).decode("utf-8")
        self.server.requests.append({"body": raw, "json": json.loads(raw)})

        if self.server.responses:
            spec = self.server.responses.pop(0)
        else:
            spec = (500, "stub exhausted")
        if isinstance(spec, tuple):
            status, payload = spec
        else:
            status, payload = 200, spec
        if not isinstance(payload, str):
            payload = json.dumps(payload)
        encoded = payload.encode("utf-8")

        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, *args):
        pass


class StubServer:
    def __init__(self, responses):
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), StubHandler)
        self.httpd.daemon_threads = True
        self.httpd.requests = []
        self.httpd.responses = list(responses)
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()

    @property
    def url(self):
        return "http://127.0.0.1:%d" % self.httpd.server_address[1]

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.thread.join(timeout=5)


class EvaluatorContract(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        self.servers = []
        self.audit_counter = 0
        self.last_audit_path = None

    def tearDown(self):
        for server in self.servers:
            server.close()
        self.temporary.cleanup()

    def serve(self, responses):
        server = StubServer(responses)
        self.servers.append(server)
        return server

    def write(self, name, text):
        path = self.directory / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return str(path)

    def base_environment(self, server, template=None, enabled="true", max_attempts="2"):
        environment = dict(os.environ)
        environment.update(
            {
                "SMOOTH_DEVEX_DECISIONS_ENABLED": enabled,
                "SMOOTH_DEVEX_DECISIONS_BASE_URL": server.url,
                "SMOOTH_DEVEX_DECISIONS_PATH": "/v1/systemone",
                "SMOOTH_DEVEX_DECISIONS_MODEL": MODEL,
                "SMOOTH_DEVEX_DECISIONS_MIN_PROBABILITY": "0.60",
                "SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS": max_attempts,
                "SMOOTH_DEVEX_DECISIONS_TIMEOUT": TIMEOUT,
            }
        )
        environment.pop("SMOOTH_DEVEX_DECISIONS_TEMPLATE", None)
        if template is not None:
            environment["SMOOTH_DEVEX_DECISIONS_TEMPLATE"] = str(template)
        return environment

    def run_eval(
        self,
        responses,
        category="potential-bug",
        template=PLAN_TEMPLATE,
        before="before text",
        after="after text",
        evidence="evidence text",
        context="file.txt:1",
        audit=None,
        stdin=None,
        environment=None,
        include_evidence=True,
        include_audit=True,
        cwd=None,
    ):
        server = self.serve(responses)

        def input_argument(name, value):
            if value == "-":
                return "-"
            return self.write(name, value)

        arguments = ["bash", str(SCRIPT), "--category", category, "--context", context]
        arguments += ["--before", input_argument("before.txt", before)]
        arguments += ["--after", input_argument("after.txt", after)]
        if include_evidence:
            arguments += ["--evidence", input_argument("evidence.txt", evidence)]
        if include_audit:
            if audit is None:
                audit = str(self.directory / ("audit-%d.json" % self.audit_counter))
                self.audit_counter += 1
            arguments += ["--audit-file", audit]
            self.last_audit_path = audit

        run_environment = self.base_environment(server, template=template)
        if environment:
            run_environment.update(environment)

        process = subprocess.run(
            arguments,
            input=stdin,
            capture_output=True,
            text=True,
            env=run_environment,
            timeout=30,
            cwd=cwd,
        )
        return process, server.httpd.requests

    def fields(self, stdout):
        lines = [line for line in stdout.splitlines() if line.strip()]
        self.assertEqual(len(lines), 1, "expected exactly one stdout line, got: %r" % stdout)
        return dict(part.split("=", 1) for part in lines[0].split("|"))

    def read_audit(self):
        self.assertIsNotNone(self.last_audit_path)
        with open(self.last_audit_path, encoding="utf-8") as handle:
            return json.load(handle)


class PlanScoringContract(EvaluatorContract):
    def score(self, **answers):
        process, _ = self.run_eval([plan_response(**answers)], template=PLAN_TEMPLATE)
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertNotIn("Traceback", process.stderr)
        return self.fields(process.stdout)

    def test_directly_required_success_is_kept_with_zero_value(self):
        fields = self.score(coverage="directly_required", change="success", positive=0.0, high=0.0)
        self.assertEqual(fields["keep"], "true")
        self.assertEqual(fields["basis"], "coverage_override")
        self.assertEqual(fields["pct"], "0")

    def test_implicitly_needed_success_is_kept_with_low_value(self):
        fields = self.score(coverage="implicitly_needed", change="success", positive=0.0, high=0.1)
        self.assertEqual(fields["keep"], "true")
        self.assertEqual(fields["basis"], "coverage_override")
        self.assertEqual(fields["pct"], "10")

    def test_directly_required_unresolved_is_rejected(self):
        fields = self.score(coverage="directly_required", change="unresolved", positive=0.3, high=0.3)
        self.assertEqual(fields["keep"], "false")
        self.assertEqual(fields["basis"], "change_rejected")

    def test_directly_required_regression_is_rejected_despite_high_value(self):
        fields = self.score(coverage="directly_required", change="regression", positive=0.5, high=0.5)
        self.assertEqual(fields["keep"], "false")
        self.assertEqual(fields["basis"], "change_rejected")

    def test_directly_required_insufficient_evidence_is_an_advisory_rejection(self):
        fields = self.score(coverage="directly_required", change="insufficient_evidence")
        self.assertEqual(fields["keep"], "false")
        self.assertEqual(fields["basis"], "insufficient_evidence")
        self.assertEqual(fields["fallback"], "false")

    def test_required_success_with_high_value_reports_coverage_override(self):
        fields = self.score(coverage="directly_required", change="success", positive=0.3, high=0.3)
        self.assertEqual(fields["keep"], "true")
        self.assertEqual(fields["basis"], "coverage_override")
        self.assertEqual(fields["pct"], "60")

    def test_non_required_below_boundary_is_rejected(self):
        fields = self.score(coverage="nice_to_have", change="success", positive=0.3, high=0.29)
        self.assertEqual(fields["keep"], "false")
        self.assertEqual(fields["basis"], "value_below_threshold")
        self.assertEqual(fields["pct"], "59")

    def test_below_boundary_that_rounds_to_the_boundary_is_still_rejected(self):
        fields = self.score(coverage="nice_to_have", change="success", positive=0.3, high=0.2984)
        self.assertEqual(fields["pct"], "60")
        self.assertEqual(fields["keep"], "false")
        self.assertEqual(fields["basis"], "value_below_threshold")

    def test_non_required_at_boundary_is_kept(self):
        fields = self.score(coverage="nice_to_have", change="success", positive=0.3, high=0.3)
        self.assertEqual(fields["keep"], "true")
        self.assertEqual(fields["basis"], "value_threshold")
        self.assertEqual(fields["pct"], "60")

    def test_non_required_above_boundary_is_kept(self):
        fields = self.score(coverage="not_required", change="success", positive=0.3, high=0.31)
        self.assertEqual(fields["keep"], "true")
        self.assertEqual(fields["basis"], "value_threshold")
        self.assertEqual(fields["pct"], "61")

    def test_non_required_unresolved_is_rejected(self):
        fields = self.score(coverage="not_required", change="unresolved", positive=0.5, high=0.5)
        self.assertEqual(fields["keep"], "false")
        self.assertEqual(fields["basis"], "change_rejected")

    def test_pct_reports_value_sum_even_when_coverage_overrides(self):
        fields = self.score(coverage="directly_required", change="success", positive=0.1, high=0.1)
        self.assertEqual(fields["pct"], "20")
        self.assertEqual(fields["keep"], "true")
        self.assertEqual(fields["basis"], "coverage_override")


class QuestionRoutingContract(EvaluatorContract):
    CORRECTION = {"feature-gap", "potential-bug", "architectural-issue"}
    REDUCTION = {"yagni", "kiss", "clean-code"}

    def captured_questions(self, category, template):
        response = plan_response() if template == PLAN_TEMPLATE else code_response()
        process, requests = self.run_eval([response], category=category, template=template)
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(len(requests), 1)
        questions = requests[0]["json"]["questions"]
        for question in questions.values():
            self.assertNotIn("instructions_by_category", question)
        return questions

    def test_all_six_categories_map_to_the_right_wording_in_both_modes(self):
        for template in (PLAN_TEMPLATE, BUILD_TEMPLATE):
            for category in sorted(self.CORRECTION | self.REDUCTION):
                with self.subTest(template=template.name, category=category):
                    questions = self.captured_questions(category, template)
                    instructions = questions["change_assessment"]["instructions"]
                    if category in self.CORRECTION:
                        self.assertIn("resolve the failure", instructions)
                        self.assertIn("without introducing a new failure", instructions)
                    else:
                        self.assertIn("simplify or remove content", instructions)
                        self.assertIn("cited rule", instructions)

    def test_no_question_assumes_the_edit_adds_an_element(self):
        for category in sorted(self.CORRECTION | self.REDUCTION):
            with self.subTest(category=category):
                questions = self.captured_questions(category, PLAN_TEMPLATE)
                for question in questions.values():
                    self.assertNotIn("including this element", question["instructions"])
                    self.assertNotIn("including this element", json.dumps(question["criteria"]))

    def test_plan_template_has_the_four_questions(self):
        questions = self.captured_questions("potential-bug", PLAN_TEMPLATE)
        self.assertEqual(
            set(questions),
            {"change_assessment", "requirement_coverage", "design_necessity", "architectural_value"},
        )

    def test_code_template_keeps_its_questions(self):
        questions = self.captured_questions("kiss", BUILD_TEMPLATE)
        self.assertEqual(
            set(questions),
            {"change_assessment", "developer_value", "necessity", "primary_value_category"},
        )

    def test_code_correction_category_gets_correction_wording(self):
        questions = self.captured_questions("potential-bug", BUILD_TEMPLATE)
        self.assertIn("resolve the failure", questions["change_assessment"]["instructions"])

    def test_clean_code_assesses_a_cited_rule_correction(self):
        questions = self.captured_questions("clean-code", PLAN_TEMPLATE)
        instructions = questions["change_assessment"]["instructions"]
        self.assertIn("cited rule", instructions)
        self.assertIn("preserving every required behavior", instructions)

    def test_deletion_is_assessed_without_an_additive_assumption(self):
        questions = self.captured_questions("yagni", PLAN_TEMPLATE)
        instructions = questions["change_assessment"]["instructions"]
        self.assertIn("simplify or remove content", instructions)
        self.assertNotIn("add", instructions)


class SummaryContract(EvaluatorContract):
    def test_plan_summary_reports_every_answer(self):
        response = plan_response(
            coverage="directly_required",
            change="success",
            necessity="important",
            positive=0.2,
            high=0.1,
            confidence=0.42,
            score=2.2,
        )
        response["answers"]["change_assessment"]["confidence"] = 0.11
        response["answers"]["requirement_coverage"]["confidence"] = 0.22
        process, _ = self.run_eval([response], template=PLAN_TEMPLATE)
        fields = self.fields(process.stdout)
        self.assertEqual(fields["coverage"], "directly_required")
        self.assertEqual(fields["change"], "success")
        self.assertEqual(fields["necessity"], "important")
        self.assertEqual(fields["value"], "positive")
        self.assertEqual(fields["pct"], "30")
        self.assertEqual(fields["confidence"], "0.42")
        self.assertEqual(fields["basis"], "coverage_override")
        self.assertEqual(fields["fallback"], "false")

    def test_plan_value_threshold_basis_is_distinguished(self):
        response = plan_response(coverage="nice_to_have", change="success", positive=0.3, high=0.3)
        process, _ = self.run_eval([response], template=PLAN_TEMPLATE)
        fields = self.fields(process.stdout)
        self.assertEqual(fields["basis"], "value_threshold")

    def test_plan_insufficient_evidence_basis_is_distinguished(self):
        response = plan_response(
            coverage="not_required", change="insufficient_evidence", positive=0.5, high=0.5
        )
        process, _ = self.run_eval([response], template=PLAN_TEMPLATE)
        fields = self.fields(process.stdout)
        self.assertEqual(fields["keep"], "false")
        self.assertEqual(fields["basis"], "insufficient_evidence")

    def test_plan_value_label_comes_from_template_criteria_not_response_legend(self):
        response = plan_response(score=3.0)
        response["answers"]["architectural_value"]["legend"] = {
            "0": "bogus",
            "1": "bogus",
            "2": "bogus",
            "3": "bogus",
        }
        process, _ = self.run_eval([response], template=PLAN_TEMPLATE)
        fields = self.fields(process.stdout)
        self.assertEqual(fields["value"], "high")

    def test_code_summary_prints_change_without_changing_scoring(self):
        response = code_response(
            change="regression",
            closes=0.3,
            improves=0.3,
            necessity="optional",
            primary="maintainability",
            confidence=0.33,
        )
        process, _ = self.run_eval([response], template=BUILD_TEMPLATE)
        fields = self.fields(process.stdout)
        self.assertEqual(fields["keep"], "true")
        self.assertEqual(fields["pct"], "60")
        self.assertEqual(fields["change"], "regression")
        self.assertEqual(fields["necessity"], "optional")
        self.assertEqual(fields["value"], "maintainability")
        self.assertEqual(fields["confidence"], "0.33")
        self.assertNotIn("coverage", fields)


class EvidencePayloadContract(EvaluatorContract):
    def test_evidence_reaches_state_exactly(self):
        evidence = (
            "Finding RL-001\nFailure: publish before prerequisite\nFix: reorder\n"
            "Requirement: release must publish after its prerequisite exists."
        )
        _, requests = self.run_eval([plan_response()], template=PLAN_TEMPLATE, evidence=evidence)
        state = requests[0]["json"]["state"]
        self.assertIn(
            "## Evidence (failure scenario or cited requirement and proposed fix):\n" + evidence,
            state,
        )

    def test_multiline_unicode_quotes_and_literal_placeholders_survive(self):
        before = 'Quote "x" — ünïcode\n{{AFTER}} {{EVIDENCE}}'
        after = 'Quote "y" — ünïcode\n{{BEFORE}} {{CONTEXT}}'
        evidence = '{{BEFORE}} {{AFTER}} {{CONTEXT}} {{CATEGORY}} {{EVIDENCE}}\nline 2 "quoted" — ünïcode'
        _, requests = self.run_eval(
            [plan_response()],
            template=PLAN_TEMPLATE,
            before=before,
            after=after,
            evidence=evidence,
        )
        state = requests[0]["json"]["state"]
        self.assertIn(before, state)
        self.assertIn(after, state)
        self.assertIn(evidence, state)

    def test_stdin_evidence_source(self):
        evidence = "stdin evidence line"
        _, requests = self.run_eval(
            [plan_response()], template=PLAN_TEMPLATE, evidence="-", stdin=evidence
        )
        state = requests[0]["json"]["state"]
        self.assertIn("## Evidence (failure scenario or cited requirement and proposed fix):\n" + evidence, state)

    def test_stdin_before_source(self):
        before = "stdin before text"
        _, requests = self.run_eval(
            [plan_response()], template=PLAN_TEMPLATE, before="-", stdin=before
        )
        state = requests[0]["json"]["state"]
        self.assertIn("## Before (current plan text):\n" + before, state)

    def test_multiple_stdin_sources_are_rejected_without_a_request(self):
        process, requests = self.run_eval(
            [], template=PLAN_TEMPLATE, before="-", evidence="-", stdin="x"
        )
        self.assertEqual(process.returncode, 1)
        self.assertIn("at most one", process.stderr)
        self.assertEqual(requests, [])

    def test_empty_after_text_is_valid_for_deletion(self):
        process, requests = self.run_eval(
            [plan_response(change="success")], template=PLAN_TEMPLATE, after=""
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(len(requests), 1)
        state = requests[0]["json"]["state"]
        self.assertIn("## After (proposed change):\n\n\n## Evidence", state)

    def test_trailing_newlines_are_preserved_in_files(self):
        before = "before line\n"
        after = "after line\n\n"
        evidence = "evidence line\n\n"
        _, requests = self.run_eval(
            [plan_response()],
            template=PLAN_TEMPLATE,
            before=before,
            after=after,
            evidence=evidence,
        )
        state = requests[0]["json"]["state"]
        self.assertIn(
            "## Before (current plan text):\n" + before + "\n\n## After (proposed change):",
            state,
        )
        self.assertIn(
            "## After (proposed change):\n"
            + after
            + "\n\n## Evidence (failure scenario or cited requirement and proposed fix):",
            state,
        )
        self.assertIn(
            "## Evidence (failure scenario or cited requirement and proposed fix):\n"
            + evidence
            + "\n\n## Section and location:",
            state,
        )
        audit = self.read_audit()
        self.assertEqual(audit["evaluation"]["state"], state)

    def test_stdin_preserves_trailing_newlines_for_each_source(self):
        for source in ("before", "after", "evidence"):
            with self.subTest(source=source):
                payload = "stdin line\n\n"
                _, requests = self.run_eval(
                    [plan_response()],
                    template=PLAN_TEMPLATE,
                    stdin=payload,
                    **{source: "-"},
                )
                state = requests[0]["json"]["state"]
                self.assertIn(payload + "\n\n##", state)


class ResponseValidationContract(EvaluatorContract):
    def expect_invalid(self, invalid_response):
        process, requests = self.run_eval(
            [invalid_response, invalid_response],
            template=PLAN_TEMPLATE,
            environment={"SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS": "2"},
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertNotIn("Traceback", process.stderr)
        self.assertEqual(len(requests), 2)
        fields = self.fields(process.stdout)
        self.assertEqual(fields["fallback"], "true")
        self.assertEqual(fields["keep"], "false")
        return process

    def test_missing_answer_is_invalid(self):
        response = plan_response()
        del response["answers"]["change_assessment"]
        self.expect_invalid(response)

    def test_wrong_answer_type_is_invalid(self):
        response = plan_response()
        response["answers"]["requirement_coverage"] = []
        self.expect_invalid(response)

    def test_null_required_numeric_value_is_invalid(self):
        response = plan_response()
        response["answers"]["architectural_value"]["confidence"] = None
        self.expect_invalid(response)

    def test_boolean_as_number_is_invalid(self):
        response = plan_response()
        response["answers"]["architectural_value"]["confidence"] = True
        self.expect_invalid(response)
        response = plan_response()
        response["answers"]["architectural_value"]["probabilities"]["2"] = True
        self.expect_invalid(response)

    def test_non_finite_probability_is_invalid(self):
        response = plan_response()
        response["answers"]["architectural_value"]["probabilities"]["2"] = float("nan")
        self.expect_invalid(response)
        response = plan_response()
        response["answers"]["architectural_value"]["probabilities"]["3"] = float("inf")
        self.expect_invalid(response)

    def test_out_of_range_probability_is_invalid(self):
        response = plan_response()
        response["answers"]["architectural_value"]["probabilities"]["2"] = 1.5
        self.expect_invalid(response)
        response = plan_response()
        response["answers"]["requirement_coverage"]["probabilities"]["directly_required"] = -0.1
        self.expect_invalid(response)

    def test_missing_probability_is_invalid_not_zero(self):
        response = plan_response()
        del response["answers"]["architectural_value"]["probabilities"]["2"]
        self.expect_invalid(response)

    def test_probability_total_must_be_one(self):
        response = plan_response()
        response["answers"]["architectural_value"]["probabilities"] = {
            "0": 0.0,
            "1": 0.0,
            "2": 1.0,
            "3": 1.0,
        }
        self.expect_invalid(response)

        response = plan_response()
        response["answers"]["architectural_value"]["probabilities"] = {
            "0": 0.0,
            "1": 0.0,
            "2": 0.0,
            "3": 0.0,
        }
        self.expect_invalid(response)

        response = plan_response()
        for key in response["answers"]["requirement_coverage"]["probabilities"]:
            response["answers"]["requirement_coverage"]["probabilities"][key] = 0.0
        self.expect_invalid(response)

    def test_probability_total_within_tolerance_is_accepted(self):
        response = plan_response(positive=0.3, high=0.3)
        response["answers"]["architectural_value"]["probabilities"]["2"] = 0.3 + 5e-7
        process, _ = self.run_eval([response], template=PLAN_TEMPLATE)
        self.assertEqual(process.returncode, 0, process.stderr)
        fields = self.fields(process.stdout)
        self.assertEqual(fields["fallback"], "false")

    def test_invalid_choice_is_invalid(self):
        response = plan_response()
        response["answers"]["requirement_coverage"]["choice"] = "maybe"
        self.expect_invalid(response)

    def test_out_of_range_score_is_invalid(self):
        response = plan_response()
        response["answers"]["architectural_value"]["score"] = 99
        self.expect_invalid(response)

    def test_wrong_mode_response_is_invalid(self):
        self.expect_invalid(code_response())

    def test_extra_answer_is_invalid(self):
        response = plan_response()
        response["answers"]["developer_value"] = code_response()["answers"]["developer_value"]
        self.expect_invalid(response)

    def test_invalid_then_valid_recovers(self):
        invalid = plan_response()
        del invalid["answers"]["change_assessment"]
        process, requests = self.run_eval(
            [invalid, plan_response()],
            template=PLAN_TEMPLATE,
            environment={"SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS": "2"},
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(len(requests), 2)
        fields = self.fields(process.stdout)
        self.assertEqual(fields["fallback"], "false")
        audit = self.read_audit()
        self.assertEqual(
            [attempt["status"] for attempt in audit["attempts"]],
            ["invalid_response", "valid"],
        )
        self.assertIn("missing", audit["attempts"][0]["reason"])

    def test_exhausted_retries_produce_one_fallback_summary(self):
        invalid = plan_response()
        del invalid["answers"]["design_necessity"]
        process, requests = self.run_eval(
            [invalid, invalid],
            template=PLAN_TEMPLATE,
            environment={"SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS": "2"},
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(len(requests), 2)
        self.assertEqual(len([line for line in process.stdout.splitlines() if line]), 1)
        self.assertIn("evaluation unavailable", process.stderr)
        audit = self.read_audit()
        self.assertEqual(len(audit["attempts"]), 2)
        self.assertIn("no valid response after 2 attempt", audit["result"]["fallback_reason"])

    def test_template_without_change_assessment_is_refused(self):
        obsolete = json.loads(PLAN_TEMPLATE.read_text(encoding="utf-8"))
        del obsolete["questions"]["change_assessment"]
        obsolete_path = self.directory / "obsolete-plan.json"
        obsolete_path.write_text(json.dumps(obsolete), encoding="utf-8")
        process, requests = self.run_eval([plan_response()], template=obsolete_path)
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(requests, [])
        fields = self.fields(process.stdout)
        self.assertEqual(fields["fallback"], "true")
        self.assertIn("change_assessment", process.stderr)

    def test_template_without_evidence_placeholder_is_refused(self):
        broken = json.loads(PLAN_TEMPLATE.read_text(encoding="utf-8"))
        broken["state"] = broken["state"].replace("{{EVIDENCE}}", "")
        broken_path = self.directory / "broken-plan.json"
        broken_path.write_text(json.dumps(broken), encoding="utf-8")
        process, requests = self.run_eval([plan_response()], template=broken_path)
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(requests, [])
        self.assertIn("EVIDENCE", process.stderr)

    def test_template_without_category_mapping_is_refused(self):
        broken = json.loads(PLAN_TEMPLATE.read_text(encoding="utf-8"))
        broken["category_groups"] = {"correction": ["potential-bug"]}
        broken_path = self.directory / "unmapped-category.json"
        broken_path.write_text(json.dumps(broken), encoding="utf-8")
        process, requests = self.run_eval(
            [plan_response()], template=broken_path, category="clean-code"
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(requests, [])
        self.assertIn("category_groups", process.stderr)


class AuditContract(EvaluatorContract):
    def test_success_audit_records_request_and_result(self):
        response = plan_response(
            coverage="directly_required", change="success", positive=0.1, high=0.1
        )
        process, requests = self.run_eval([response], template=PLAN_TEMPLATE)
        audit = self.read_audit()
        self.assertEqual(audit["schema_version"], 1)
        self.assertEqual(audit["evaluation"]["category"], "potential-bug")
        self.assertEqual(audit["evaluation"]["mode"], "plan")
        self.assertEqual(audit["evaluation"]["model"], MODEL)
        self.assertAlmostEqual(audit["evaluation"]["threshold"], 0.60)
        self.assertEqual(audit["evaluation"]["template"]["mode"], "plan")
        self.assertRegex(audit["evaluation"]["template"]["sha256"], r"^[0-9a-f]{64}$")
        self.assertEqual(audit["evaluation"]["state"], requests[0]["json"]["state"])
        self.assertEqual(audit["evaluation"]["questions"], requests[0]["json"]["questions"])
        self.assertEqual(len(audit["attempts"]), 1)
        self.assertEqual(audit["attempts"][0]["status"], "valid")
        self.assertEqual(audit["attempts"][0]["response"], json.dumps(response))
        self.assertEqual(audit["result"]["keep"], True)
        self.assertEqual(audit["result"]["basis"], "coverage_override")
        self.assertIn("audit=" + str(self.last_audit_path), process.stdout)

    def test_reject_audit_records_reason(self):
        response = plan_response(coverage="directly_required", change="regression")
        self.run_eval([response], template=PLAN_TEMPLATE)
        audit = self.read_audit()
        self.assertEqual(audit["result"]["keep"], False)
        self.assertEqual(audit["result"]["basis"], "change_rejected")

    def test_retry_audit_preserves_unsuccessful_attempt(self):
        invalid = plan_response()
        del invalid["answers"]["design_necessity"]
        self.run_eval(
            [invalid, plan_response()],
            template=PLAN_TEMPLATE,
            environment={"SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS": "2"},
        )
        audit = self.read_audit()
        self.assertEqual(
            [attempt["status"] for attempt in audit["attempts"]],
            ["invalid_response", "valid"],
        )
        self.assertEqual(audit["attempts"][0]["response"], json.dumps(invalid))
        self.assertIn("missing", audit["attempts"][0]["reason"])

    def test_http_error_body_is_preserved_and_retry_recovers(self):
        error_body = json.dumps({"error": "model loading, please retry", "id": "review-probe"})
        process, requests = self.run_eval(
            [(503, error_body), plan_response()],
            template=PLAN_TEMPLATE,
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        fields = self.fields(process.stdout)
        self.assertEqual(fields["fallback"], "false")
        self.assertEqual(len(requests), 2)
        audit = self.read_audit()
        first = audit["attempts"][0]
        self.assertEqual(first["status"], "http_error")
        self.assertEqual(first["http_status"], 503)
        self.assertEqual(first["response"], error_body)
        self.assertNotIn("headers", first)
        self.assertEqual(audit["attempts"][1]["status"], "valid")

    def test_exhausted_http_errors_preserve_status_and_body(self):
        error_body = json.dumps({"error": "model loading, please retry"})
        process, requests = self.run_eval(
            [(503, error_body), (503, error_body)],
            template=PLAN_TEMPLATE,
            environment={"SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS": "2"},
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(len(requests), 2)
        fields = self.fields(process.stdout)
        self.assertEqual(fields["fallback"], "true")
        audit = self.read_audit()
        for attempt in audit["attempts"]:
            self.assertEqual(attempt["status"], "http_error")
            self.assertEqual(attempt["http_status"], 503)
            self.assertEqual(attempt["response"], error_body)
            self.assertNotIn("headers", attempt)
        self.assertIn("HTTP 503", audit["result"]["fallback_reason"])

    def test_exhausted_retries_audit_records_fallback_reason(self):
        invalid = plan_response()
        del invalid["answers"]["change_assessment"]
        self.run_eval(
            [invalid, invalid],
            template=PLAN_TEMPLATE,
            environment={"SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS": "2"},
        )
        audit = self.read_audit()
        self.assertTrue(audit["result"]["fallback"])
        self.assertIn("no valid response", audit["result"]["fallback_reason"])
        self.assertEqual(len(audit["attempts"]), 2)

    def test_different_audit_paths_do_not_overwrite(self):
        path_a = str(self.directory / "a.json")
        path_b = str(self.directory / "b.json")
        self.run_eval(
            [plan_response(coverage="directly_required", change="success")],
            template=PLAN_TEMPLATE,
            audit=path_a,
        )
        self.run_eval(
            [plan_response(coverage="not_required", change="unresolved")],
            template=PLAN_TEMPLATE,
            audit=path_b,
        )
        with open(path_a, encoding="utf-8") as handle:
            first = json.load(handle)
        with open(path_b, encoding="utf-8") as handle:
            second = json.load(handle)
        self.assertTrue(first["result"]["keep"])
        self.assertFalse(second["result"]["keep"])
        self.assertNotEqual(
            first["attempts"][0]["response"], second["attempts"][0]["response"]
        )

    def test_same_audit_path_writes_a_new_file_and_preserves_the_first(self):
        path = str(self.directory / "same.json")
        self.run_eval(
            [plan_response(coverage="directly_required", change="success")],
            template=PLAN_TEMPLATE,
            audit=path,
        )
        with open(path, encoding="utf-8") as handle:
            first_contents = handle.read()
        process, _ = self.run_eval(
            [plan_response(coverage="not_required", change="unresolved")],
            template=PLAN_TEMPLATE,
            audit=path,
        )
        with open(path, encoding="utf-8") as handle:
            self.assertEqual(handle.read(), first_contents)
        second_path = str(self.directory / "same-2.json")
        self.assertTrue(Path(second_path).exists())
        self.assertIn("audit=" + second_path, process.stdout)

    def test_concurrent_writes_to_the_same_path_keep_every_audit(self):
        count = 6
        server = self.serve([plan_response() for _ in range(count)])
        before = self.write("concurrent-before.txt", "before")
        after = self.write("concurrent-after.txt", "after")
        evidence = self.write("concurrent-evidence.txt", "evidence")
        audit_path = str(self.directory / "concurrent.json")
        arguments = [
            "bash",
            str(SCRIPT),
            "--category",
            "potential-bug",
            "--before",
            before,
            "--after",
            after,
            "--evidence",
            evidence,
            "--context",
            "file.txt:1",
            "--audit-file",
            audit_path,
        ]
        environment = self.base_environment(server, template=PLAN_TEMPLATE)
        processes = [
            subprocess.Popen(
                arguments,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=environment,
            )
            for _ in range(count)
        ]
        results = [process.communicate(timeout=30) for process in processes]
        for process, (stdout, stderr) in zip(processes, results):
            self.assertEqual(process.returncode, 0, stderr)
            self.assertNotIn("audit=failed", stdout)
        audits = list(self.directory.glob("concurrent*.json"))
        self.assertEqual(len(audits), count)
        self.assertEqual(list(self.directory.glob(".audit-*")), [])
        for path in audits:
            with open(path, encoding="utf-8") as handle:
                document = json.load(handle)
            self.assertIn("attempts", document)
            self.assertIn("result", document)

    def test_unwritable_audit_destination_is_reported_without_crashing(self):
        directory_path = self.directory / "audit-directory"
        directory_path.mkdir()
        process, requests = self.run_eval(
            [plan_response()], template=PLAN_TEMPLATE, audit=str(directory_path)
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(len(requests), 1)
        self.assertIn("audit-write failed", process.stderr)
        fields = self.fields(process.stdout)
        self.assertEqual(fields["audit"], "failed")
        self.assertEqual(fields["fallback"], "false")

    def test_audit_json_stays_valid_for_non_json_raw_response(self):
        process, _ = self.run_eval(
            ["not json {", "not json {"],
            template=PLAN_TEMPLATE,
            environment={"SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS": "2"},
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        audit = self.read_audit()
        self.assertTrue(audit["result"]["fallback"])
        self.assertEqual(audit["attempts"][0]["response"], "not json {")


class CompatibilityContract(EvaluatorContract):
    def test_disabled_makes_no_request_and_needs_no_new_flags(self):
        process, requests = self.run_eval(
            [],
            template=None,
            include_evidence=False,
            include_audit=False,
            environment={"SMOOTH_DEVEX_DECISIONS_ENABLED": "false"},
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(requests, [])
        fields = self.fields(process.stdout)
        self.assertEqual(fields["value"], "disabled")
        self.assertEqual(fields["fallback"], "true")

    def test_legacy_enabled_caller_missing_evidence_is_a_usage_error(self):
        process, requests = self.run_eval(
            [plan_response()],
            template=PLAN_TEMPLATE,
            include_evidence=False,
            environment={"SMOOTH_DEVEX_DECISIONS_ENABLED": "true"},
        )
        self.assertEqual(process.returncode, 1)
        self.assertIn("--evidence is required", process.stderr)
        self.assertIn("legacy enabled callers", process.stderr)
        self.assertEqual(requests, [])

    def test_legacy_enabled_caller_missing_audit_is_a_usage_error(self):
        process, requests = self.run_eval(
            [plan_response()], template=PLAN_TEMPLATE, include_audit=False
        )
        self.assertEqual(process.returncode, 1)
        self.assertIn("--audit-file is required", process.stderr)
        self.assertEqual(requests, [])

    def test_missing_input_file_is_an_argument_error_before_network(self):
        server = self.serve([plan_response()])
        arguments = [
            "bash",
            str(SCRIPT),
            "--category",
            "potential-bug",
            "--before",
            str(self.directory / "absent.md"),
            "--after",
            self.write("after.txt", "after"),
            "--evidence",
            self.write("evidence.txt", "evidence"),
            "--context",
            "file.txt:1",
            "--audit-file",
            str(self.directory / "audit.json"),
        ]
        process = subprocess.run(
            arguments,
            capture_output=True,
            text=True,
            env=self.base_environment(server, template=PLAN_TEMPLATE),
            timeout=30,
        )
        self.assertEqual(process.returncode, 1)
        self.assertIn("before file not found", process.stderr)
        self.assertEqual(server.httpd.requests, [])

    def test_unreadable_input_file_is_an_argument_error_without_stale_input(self):
        if os.name == "nt":
            self.skipTest("mode-based readability is POSIX-specific")
        if hasattr(os, "geteuid") and os.geteuid() == 0:
            self.skipTest("root can read mode-000 files")
        server = self.serve([plan_response()])
        before = self.write("readable-before.txt", "before text")
        after = self.write("unreadable-after.txt", "after text")
        evidence = self.write("readable-evidence.txt", "evidence text")
        os.chmod(after, 0)
        try:
            arguments = [
                "bash",
                str(SCRIPT),
                "--category",
                "potential-bug",
                "--before",
                before,
                "--after",
                after,
                "--evidence",
                evidence,
                "--context",
                "file.txt:1",
                "--audit-file",
                str(self.directory / "unreadable-audit.json"),
            ]
            process = subprocess.run(
                arguments,
                capture_output=True,
                text=True,
                env=self.base_environment(server, template=PLAN_TEMPLATE),
                timeout=30,
            )
        finally:
            os.chmod(after, 0o600)
        self.assertEqual(process.returncode, 1)
        self.assertIn("after file not readable", process.stderr)
        self.assertEqual(server.httpd.requests, [])

    def test_unknown_category_is_an_argument_error_before_network(self):
        process, requests = self.run_eval([plan_response()], category="not-a-category")
        self.assertEqual(process.returncode, 1)
        self.assertIn("invalid category", process.stderr)
        self.assertEqual(requests, [])

    def test_base_url_with_embedded_credentials_is_rejected_before_network(self):
        process, requests = self.run_eval(
            [plan_response()],
            template=PLAN_TEMPLATE,
            environment={
                "SMOOTH_DEVEX_DECISIONS_BASE_URL": "http://user:secret@127.0.0.1:1/v1/systemone"
            },
        )
        self.assertEqual(process.returncode, 1)
        self.assertIn("must not embed credentials", process.stderr)
        self.assertEqual(requests, [])

    def test_code_scoring_stays_closes_gap_plus_improves_quality(self):
        process, _ = self.run_eval(
            [code_response(closes=0.35, improves=0.25)],
            category="potential-bug",
            template=BUILD_TEMPLATE,
        )
        fields = self.fields(process.stdout)
        self.assertEqual(fields["pct"], "60")
        self.assertEqual(fields["keep"], "true")

        process, _ = self.run_eval(
            [code_response(closes=0.3, improves=0.29)],
            category="potential-bug",
            template=BUILD_TEMPLATE,
        )
        fields = self.fields(process.stdout)
        self.assertEqual(fields["pct"], "59")
        self.assertEqual(fields["keep"], "false")

    def test_default_template_resolves_from_a_different_cwd(self):
        process, requests = self.run_eval(
            [code_response()], category="kiss", template=None, cwd=str(self.directory)
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(len(requests), 1)
        self.assertIn("developer_value", requests[0]["json"]["questions"])

    def test_copied_global_skill_layout_works(self):
        global_dir = self.directory / "global" / "ai-ralph-loop"
        shutil.copytree(SKILL_DIR, global_dir)
        global_script = global_dir / "decisions" / "scripts" / "decision-evaluate.sh"
        server = self.serve([code_response()])
        arguments = [
            "bash",
            str(global_script),
            "--category",
            "kiss",
            "--before",
            self.write("global-before.txt", "before"),
            "--after",
            self.write("global-after.txt", "after"),
            "--evidence",
            self.write("global-evidence.txt", "evidence"),
            "--context",
            "file.txt:1",
            "--audit-file",
            str(self.directory / "global-audit.json"),
        ]
        process = subprocess.run(
            arguments,
            capture_output=True,
            text=True,
            env=self.base_environment(server, template=None),
            timeout=30,
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(len(server.httpd.requests), 1)
        self.assertIn("developer_value", server.httpd.requests[0]["json"]["questions"])

    def test_stdout_is_one_pipe_delimited_line(self):
        process, _ = self.run_eval([plan_response()], template=PLAN_TEMPLATE)
        lines = [line for line in process.stdout.splitlines() if line]
        self.assertEqual(len(lines), 1)
        self.assertIn("|", lines[0])
        self.assertEqual(process.stderr, "")

    def test_reject_is_reported_and_exits_zero(self):
        process, _ = self.run_eval(
            [plan_response(change="regression", coverage="directly_required")],
            template=PLAN_TEMPLATE,
        )
        self.assertEqual(process.returncode, 0)
        fields = self.fields(process.stdout)
        self.assertEqual(fields["keep"], "false")


if __name__ == "__main__":
    unittest.main(verbosity=2)
