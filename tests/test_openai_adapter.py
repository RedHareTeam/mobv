"""Mocked model tests: no network access or API key is needed."""

from __future__ import annotations

import csv
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from openai_adapter import OpenAIClassifier, config_value, response_schema
from voc_ops import INPUT_COLUMNS, load_input, run


ROOT = Path(__file__).resolve().parents[1]


def response_for(voc_id: str, *, priority: str = "P2") -> dict:
    prediction = {
        "voc_id": voc_id, "summary": "인증 메일이 도착하지 않음",
        "product_area": "AUTH", "category": "ACCOUNT",
        "secondary_category": None, "priority": priority, "owner": "OPERATIONS",
        "secondary_owner": None, "sla": {"P0": "즉시 확인", "P1": "당일", "P2": "3영업일 이내", "P3": "5영업일 이내"}[priority],
        "confidence": "MEDIUM", "reason": "인증 메일 미도착 신고",
    }
    return {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": json.dumps(prediction, ensure_ascii=False)}]}]}


def one_row_csv(target: Path) -> None:
    item = next(row for row in load_input(ROOT / "data" / "development_voc.csv") if row["voc_id"] == "DEV-020")
    with target.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=INPUT_COLUMNS)
        writer.writeheader()
        writer.writerow(item)


class OpenAIAdapterTests(unittest.TestCase):
    def test_schema_and_payload_redaction(self) -> None:
        schema = response_schema()
        self.assertEqual(set(schema["required"]), set(schema["properties"]))
        self.assertFalse(schema["additionalProperties"])
        captured = []

        def transport(payload, api_key, timeout):
            captured.append(payload)
            self.assertEqual(api_key, "test-key")
            return response_for("DEV-020")

        predictor = OpenAIClassifier("test-model", api_key="test-key", transport=transport)
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.csv"
            one_row_csv(source)
            log = run(source, Path(directory) / "output", predictor, retry_delay=0)
        self.assertEqual(log["success_count"], 1)
        self.assertEqual(log["model_name"], "test-model")
        self.assertFalse(captured[0]["store"])
        self.assertNotIn("test.user@example.com", json.dumps(captured[0], ensure_ascii=False))
        self.assertIn("[EMAIL]", json.dumps(captured[0], ensure_ascii=False))

    def test_invalid_output_retries_then_enters_review_queue(self) -> None:
        calls = []

        def transport(payload, api_key, timeout):
            calls.append(1)
            return response_for("WRONG-ID")

        predictor = OpenAIClassifier("test-model", api_key="test-key", transport=transport)
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.csv"
            one_row_csv(source)
            output = Path(directory) / "output"
            log = run(source, output, predictor, max_attempts=2, retry_delay=0)
            with (output / "review_queue.csv").open(encoding="utf-8-sig", newline="") as handle:
                rows = list(csv.DictReader(handle))
        self.assertEqual(len(calls), 2)
        self.assertEqual(log["failure_count"], 1)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["processing_status"], "FAILED")
        self.assertEqual(rows[0]["review_status"], "PENDING")
        self.assertEqual(rows[0]["review_flags"], "INVALID_OUTPUT")
        self.assertNotIn("test.user@example.com", rows[0]["user_text_redacted"])

    def test_missing_key_fails_before_api_call(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            with patch("openai_adapter.ENV_PATH", Path(directory) / ".env"):
                with patch.dict("os.environ", {"OPENAI_API_KEY": ""}):
                    with self.assertRaisesRegex(ValueError, "OPENAI_API_KEY"):
                        OpenAIClassifier("test-model")

    def test_local_dotenv_and_environment_precedence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            env_path = Path(directory) / ".env"
            env_path.write_text("OPENAI_API_KEY=file-test-key\nOPENAI_MODEL=file-test-model\n", encoding="utf-8")
            with patch("openai_adapter.ENV_PATH", env_path):
                with patch.dict("os.environ", {"OPENAI_API_KEY": "", "OPENAI_MODEL": ""}):
                    self.assertEqual(config_value("OPENAI_MODEL"), "file-test-model")
                    self.assertEqual(OpenAIClassifier("file-test-model").api_key, "file-test-key")
                with patch.dict("os.environ", {"OPENAI_API_KEY": "process-test-key"}):
                    self.assertEqual(config_value("OPENAI_API_KEY"), "process-test-key")

    def test_streamlit_secrets_are_used_after_environment_and_dotenv(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            env_path = Path(directory) / ".env"
            with patch("openai_adapter.ENV_PATH", env_path), patch(
                "openai_adapter._streamlit_secret", return_value="cloud-test-key"
            ), patch.dict("os.environ", {"OPENAI_API_KEY": ""}):
                self.assertEqual(config_value("OPENAI_API_KEY"), "cloud-test-key")

    def test_rules_override_underestimated_privacy_exposure(self) -> None:
        item = next(row for row in load_input(ROOT / "data" / "development_voc.csv") if row["voc_id"] == "DEV-008")

        def transport(payload, api_key, timeout):
            return response_for("DEV-008", priority="P3")

        predictor = OpenAIClassifier("test-model", api_key="test-key", transport=transport)
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.csv"
            with source.open("w", encoding="utf-8", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=INPUT_COLUMNS)
                writer.writeheader()
                writer.writerow(item)
            output = Path(directory) / "output"
            run(source, output, predictor, retry_delay=0)
            with (output / "classified_voc.csv").open(encoding="utf-8-sig", newline="") as handle:
                row = next(csv.DictReader(handle))
        self.assertEqual(row["ai_priority"], "P3")
        self.assertEqual(row["rule_priority"], "P0")
        self.assertIn("RULE_OVERRIDE", row["review_flags"])
        self.assertEqual(row["review_status"], "PENDING")


if __name__ == "__main__":
    unittest.main()
