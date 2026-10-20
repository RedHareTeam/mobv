"""Tests for input boundaries and the Day 3 review gate."""

from __future__ import annotations

import csv
import tempfile
import unittest
from pathlib import Path

from voc_ops import INPUT_COLUMNS, InputError, classify, load_input, redact, run


ROOT = Path(__file__).resolve().parents[1]


class PipelineTests(unittest.TestCase):
    def test_development_set_runs_without_exposing_test_contact_data(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            log = run(ROOT / "data" / "development_voc.csv", target)
            self.assertEqual(log["input_count"], 30)
            self.assertEqual(log["success_count"], 30)
            with (target / "classified_voc.csv").open(encoding="utf-8-sig", newline="") as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(len(rows), 30)
            self.assertTrue(all(row["processing_status"] == "SUCCESS" for row in rows))
            self.assertTrue(all(row["review_status"] == "PENDING" for row in rows if row["needs_review"] == "true"))
            self.assertTrue(all(row["final_category"] == "" for row in rows if row["needs_review"] == "true"))
            joined = (target / "classified_voc.csv").read_text(encoding="utf-8-sig")
            self.assertNotIn("test.user@example.com", joined)
            self.assertNotIn("010-0000-0000", joined)

    def test_invalid_input_cannot_create_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            source = target / "bad.csv"
            with source.open("w", encoding="utf-8", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=INPUT_COLUMNS)
                writer.writeheader()
                row = dict.fromkeys(INPUT_COLUMNS, "unknown")
                row.update(voc_id="X-1", received_at="2026-02-30", channel="email", platform="web", screen="login", user_text="test")
                writer.writerow(row)
            with self.assertRaises(InputError):
                run(source, target / "output")
            self.assertFalse((target / "output").exists())

    def test_privacy_issue_and_injection_are_reviewed(self) -> None:
        items = load_input(ROOT / "data" / "development_voc.csv")
        by_id = {item["voc_id"]: item for item in items}
        exposed = classify(by_id["DEV-008"], "test-run", "2026-10-19T00:00:00+09:00")
        self.assertEqual(exposed["rule_priority"], "P0")
        self.assertEqual(exposed["review_status"], "PENDING")
        injection = classify(by_id["DEV-022"], "test-run", "2026-10-19T00:00:00+09:00")
        self.assertIn("PROMPT_INJECTION", injection["review_flags"])
        self.assertNotEqual(injection["rule_priority"], "P0")

    def test_redaction(self) -> None:
        text, found = redact("test.user@example.com / 010-0000-0000")
        self.assertTrue(found)
        self.assertEqual(text, "[EMAIL] / [PHONE]")


if __name__ == "__main__":
    unittest.main()
