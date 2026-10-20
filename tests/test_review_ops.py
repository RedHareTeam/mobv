"""Human review must preserve the AI/rule trail and require reasoned edits."""

from __future__ import annotations

import csv
import tempfile
import unittest
from pathlib import Path

from review_ops import ReviewError, apply_decision, load_session, pending_rows, save_results
from voc_ops import run


ROOT = Path(__file__).resolve().parents[1]


class ReviewTests(unittest.TestCase):
    def test_approve_and_resume_preserves_original(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            run(ROOT / "data" / "development_voc.csv", target)
            source = target / "classified_voc.csv"
            reviewed = target / "reviewed_voc.csv"
            rows = load_session(source, reviewed)
            pending = pending_rows(rows)
            self.assertEqual(len(pending), 17)
            first = pending[0]
            updated = apply_decision(first, reviewed_at="2026-10-20T10:00:00+09:00")
            self.assertEqual(updated["review_status"], "APPROVED")
            self.assertEqual(updated["final_priority"], first["rule_priority"])
            self.assertEqual(updated["final_sla"], first["rule_sla"])
            rows[rows.index(first)] = updated
            save_results(reviewed, rows)
            resumed = load_session(source, reviewed)
            self.assertEqual(len(pending_rows(resumed)), 16)
            self.assertEqual(resumed[rows.index(updated)]["reviewed_at"], "2026-10-20T10:00:00+09:00")
            with source.open(encoding="utf-8-sig", newline="") as handle:
                original = next(csv.DictReader(handle))
            self.assertEqual(original["review_status"], "PENDING")

    def test_modification_requires_reason_and_derives_sla(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            run(ROOT / "data" / "development_voc.csv", target)
            row = pending_rows(load_session(target / "classified_voc.csv", target / "reviewed_voc.csv"))[0]
            with self.assertRaises(ReviewError):
                apply_decision(row, priority="P2")
            updated = apply_decision(row, priority="P2", reason="사람이 우회 방법 확인")
            self.assertEqual(updated["review_status"], "MODIFIED")
            self.assertEqual(updated["final_sla"], "3영업일 이내")
            self.assertEqual(updated["ai_priority"], row["ai_priority"])
            self.assertEqual(updated["rule_priority"], row["rule_priority"])
            self.assertEqual(updated["correction_reason"], "사람이 우회 방법 확인")

    def test_failed_model_result_cannot_be_approved_unchanged(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            run(ROOT / "data" / "development_voc.csv", target)
            row = pending_rows(load_session(target / "classified_voc.csv", target / "reviewed_voc.csv"))[0]
            failed = row | {"processing_status": "FAILED", "rule_category": "", "rule_priority": "",
                            "rule_owner": "", "rule_sla": ""}
            with self.assertRaises(ReviewError):
                apply_decision(failed)
            updated = apply_decision(failed, category="BUG", priority="P1",
                                     owner="DEVELOPMENT", reason="사람이 직접 분류")
            self.assertEqual(updated["review_status"], "MODIFIED")
            self.assertEqual(updated["processing_status"], "FAILED")

    def test_resume_rejects_different_run(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            run(ROOT / "data" / "development_voc.csv", target)
            source = target / "classified_voc.csv"
            reviewed = target / "reviewed_voc.csv"
            save_results(reviewed, load_session(source, reviewed))
            run(ROOT / "data" / "development_voc.csv", target)
            with self.assertRaises(ReviewError):
                load_session(source, reviewed)


if __name__ == "__main__":
    unittest.main()
