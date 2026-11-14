#!/usr/bin/env python3
"""L0 unit tests for the shared decision core.

Stdlib `unittest` only; no network, no subprocess. Run directly by file path:

  python3 -B .agents/_smooth-devex-shared/decisions/tests/test_decisions_core.py -v
"""

import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path

CORE_PATH = Path(__file__).resolve().parents[1] / "decisions_core.py"
SPEC = importlib.util.spec_from_file_location("decisions_core", CORE_PATH)
core = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(core)


CHOICE_QUESTION = {
    "type": "choice",
    "instructions": "Which option fits the evidence?",
    "criteria": {"keep": "preserves required behavior", "drop": "discards required behavior"},
}
SCORE_QUESTION = {
    "type": "score",
    "instructions": "Rate the value.",
    "criteria": ["harmful", "neutral", "positive"],
}


def choice_answer(choice="keep", confidence=0.5):
    other = 1.0 - 0.7
    return {
        "type": "choice",
        "choice": choice,
        "probabilities": {key: (0.7 if key == choice else other) for key in CHOICE_QUESTION["criteria"]},
        "confidence": confidence,
    }


def score_answer(score=1.0, confidence=0.5):
    return {
        "type": "score",
        "score": score,
        "probabilities": {"0": 0.2, "1": 0.4, "2": 0.4},
        "confidence": confidence,
    }


def response(**answers):
    return json.dumps({"model": "stub", "answers": answers})


class QuestionValidation(unittest.TestCase):
    def assert_rejected(self, questions, fragment):
        with self.assertRaises(core.QuestionError) as caught:
            core.validate_questions(questions)
        self.assertIn(fragment, str(caught.exception))

    def test_choice_and_score_are_accepted(self):
        questions = {"pick": CHOICE_QUESTION, "rate": SCORE_QUESTION}
        self.assertIs(core.validate_questions(questions), questions)

    def test_noul_is_rejected(self):
        noul = {"type": "noul", "instructions": "x", "criteria": ["a", "b"]}
        self.assert_rejected({"n": noul}, "unsupported type")

    def test_unknown_type_is_rejected(self):
        self.assert_rejected({"n": dict(CHOICE_QUESTION, type="rank")}, "unsupported type")

    def test_missing_instructions_is_rejected(self):
        question = {"type": "choice", "criteria": {"a": "x"}}
        self.assert_rejected({"q": question}, "no instructions")

    def test_choice_criteria_must_be_a_non_empty_object(self):
        self.assert_rejected({"q": dict(CHOICE_QUESTION, criteria=["a", "b"])}, "criteria object")
        self.assert_rejected({"q": dict(CHOICE_QUESTION, criteria={})}, "criteria object")

    def test_score_criteria_need_at_least_two_entries(self):
        self.assert_rejected({"q": dict(SCORE_QUESTION, criteria=["only"])}, "at least two criteria")


class ResponseValidation(unittest.TestCase):
    def test_valid_choice_and_score_are_accepted(self):
        questions = {"pick": CHOICE_QUESTION, "rate": SCORE_QUESTION}
        answers, reason = core.validate_response(
            response(pick=choice_answer(), rate=score_answer()), questions
        )
        self.assertEqual(reason, "")
        self.assertEqual(set(answers), {"pick", "rate"})

    def test_invalid_choice_is_rejected(self):
        questions = {"pick": CHOICE_QUESTION}
        answers, _ = core.validate_response(response(pick=choice_answer("maybe")), questions)
        self.assertIsNone(answers)

    def test_missing_probability_is_invalid_not_zero(self):
        question = {"pick": CHOICE_QUESTION}
        answer = choice_answer()
        del answer["probabilities"]["drop"]
        answers, _ = core.validate_response(response(pick=answer), question)
        self.assertIsNone(answers)

    def test_probability_total_must_be_one(self):
        questions = {"rate": SCORE_QUESTION}
        answer = score_answer()
        answer["probabilities"] = {"0": 0.5, "1": 0.5, "2": 0.5}
        answers, reason = core.validate_response(response(rate=answer), questions)
        self.assertIsNone(answers)
        self.assertIn("failed score validation", reason)

    def test_probability_total_within_tolerance_is_accepted(self):
        questions = {"rate": SCORE_QUESTION}
        answer = score_answer()
        answer["probabilities"] = {"0": 0.2, "1": 0.4, "2": 0.4 + 5e-7}
        answers, _ = core.validate_response(response(rate=answer), questions)
        self.assertIsNotNone(answers)

    def test_probability_keys_must_match_the_outgoing_criteria(self):
        questions = {"pick": CHOICE_QUESTION}
        answer = choice_answer()
        answer["probabilities"] = {"keep": 0.5, "other": 0.5}
        answers, _ = core.validate_response(response(pick=answer), questions)
        self.assertIsNone(answers)

    def test_score_out_of_range_is_rejected(self):
        questions = {"rate": SCORE_QUESTION}
        answers, _ = core.validate_response(response(rate=score_answer(score=99)), questions)
        self.assertIsNone(answers)

    def test_confidence_outside_zero_to_one_is_rejected(self):
        questions = {"pick": CHOICE_QUESTION}
        answers, _ = core.validate_response(response(pick=choice_answer(confidence=1.5)), questions)
        self.assertIsNone(answers)

    def test_answer_type_must_match_the_question_type(self):
        questions = {"pick": CHOICE_QUESTION}
        answers, reason = core.validate_response(response(pick=score_answer()), questions)
        self.assertIsNone(answers)
        self.assertIn("failed choice validation", reason)

    def test_missing_and_unexpected_answers_are_rejected(self):
        questions = {"pick": CHOICE_QUESTION}
        answers, reason = core.validate_response(response(rate=score_answer()), questions)
        self.assertIsNone(answers)
        self.assertIn("missing: pick", reason)
        self.assertIn("unexpected: rate", reason)

    def test_non_json_and_non_object_responses_are_rejected(self):
        questions = {"pick": CHOICE_QUESTION}
        self.assertEqual(core.validate_response("not json {", questions)[0], None)
        self.assertEqual(core.validate_response("[]", questions)[0], None)


class RequestBuilding(unittest.TestCase):
    def test_payload_builds_the_wire_body(self):
        payload = {"state": "the situation", "questions": {"pick": CHOICE_QUESTION}}
        body = core.build_request(payload, "d3:4b")
        self.assertEqual(body["model"], "d3:4b")
        self.assertEqual(body["state"], "the situation")
        self.assertEqual(body["questions"], payload["questions"])

    def test_context_and_question_are_rejected_as_field_names(self):
        with self.assertRaises(core.PayloadError) as caught:
            core.build_request({"context": "x", "question": {}}, "m")
        message = str(caught.exception)
        self.assertIn("context", message)
        self.assertIn("question", message)

    def test_missing_state_or_questions_is_rejected(self):
        with self.assertRaises(core.PayloadError):
            core.build_request({"questions": {"pick": CHOICE_QUESTION}}, "m")
        with self.assertRaises(core.PayloadError):
            core.build_request({"state": "x"}, "m")

    def test_empty_state_is_rejected(self):
        with self.assertRaises(core.PayloadError):
            core.build_request({"state": "", "questions": {"pick": CHOICE_QUESTION}}, "m")

    def test_payload_question_validation_is_applied(self):
        noul = {"type": "noul", "instructions": "x", "criteria": ["a", "b"]}
        with self.assertRaises(core.QuestionError):
            core.build_request({"state": "x", "questions": {"n": noul}}, "m")


class EndpointSafety(unittest.TestCase):
    def test_base_url_with_credentials_is_refused_before_any_request(self):
        payload = {"state": "x", "questions": {"pick": CHOICE_QUESTION}}
        with self.assertRaises(core.UrlError) as caught:
            core.evaluate(
                payload,
                url="http://user:secret@127.0.0.1:1/v1/systemone",
                model="m",
                max_attempts=1,
                timeout=1,
            )
        self.assertIn("must not embed credentials", str(caught.exception))

    def test_api_key_with_a_line_break_is_refused_before_any_request(self):
        payload = {"state": "x", "questions": {"pick": CHOICE_QUESTION}}
        with self.assertRaises(core.CredentialError) as caught:
            core.evaluate(
                payload,
                url="http://127.0.0.1:1",
                model="m",
                max_attempts=1,
                timeout=1,
                api_key="abc\ndef",
            )
        self.assertIn("line break", str(caught.exception))
        self.assertNotIn("abc", str(caught.exception))

    def test_redirect_handler_refuses_to_follow(self):
        self.assertIsNone(
            core._NoRedirectHandler().redirect_request(None, None, 302, "Found", {}, "http://elsewhere/")
        )

    def test_invalid_url_is_refused(self):
        payload = {"state": "x", "questions": {"pick": CHOICE_QUESTION}}
        with self.assertRaises(core.UrlError):
            core.evaluate(
                payload,
                url="not a url",
                model="m",
                max_attempts=1,
                timeout=1,
            )


class AuditWrites(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def test_audit_is_written_and_never_contains_headers(self):
        path = self.directory / "audit.json"
        status = core.write_audit({"schema_version": 1, "attempts": []}, str(path))
        self.assertEqual(status, str(path))
        document = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(document["schema_version"], 1)
        self.assertNotIn("Authorization", path.read_text(encoding="utf-8"))

    def test_existing_path_takes_the_next_free_suffix(self):
        path = self.directory / "audit.json"
        first = core.write_audit({"n": 1}, str(path))
        second = core.write_audit({"n": 2}, str(path))
        self.assertEqual(first, str(path))
        self.assertEqual(second, str(self.directory / "audit-2.json"))
        self.assertEqual(json.loads(path.read_text(encoding="utf-8"))["n"], 1)

    def test_unwritable_destination_reports_failed(self):
        directory_as_file = self.directory / "audit-directory"
        directory_as_file.mkdir()
        self.assertEqual(core.write_audit({"n": 1}, str(directory_as_file)), "failed")

    def test_no_audit_file_reports_failed_for_writers(self):
        self.assertEqual(core.write_audit({"n": 1}, ""), "failed")
        self.assertEqual(os.path.isdir(self.directory), True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
