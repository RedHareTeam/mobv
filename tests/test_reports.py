"""Check that the saved report and dashboard share operational counts."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from reports import render_weekly_report, summarize
from review_ops import load_results
from voc_ops import run


ROOT = Path(__file__).resolve().parents[1]


class ReportTests(unittest.TestCase):
    def test_run_writes_report_for_its_input_period(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            log = run(ROOT / "data" / "development_voc.csv", output)
            rows = load_results(output / "classified_voc.csv")
            report = (output / "weekly_report.md").read_text(encoding="utf-8")
            info = summarize(rows)

            self.assertEqual(info["total"], 30)
            self.assertEqual(info["pending"], log["review_count"])
            self.assertEqual(sum(info["by_date"].values()), info["total"])
            self.assertEqual(sum(info["areas"].values()), info["total"])
            self.assertEqual(sum(info["channels"].values()), info["total"])
            self.assertIn("입력 CSV 전체의 요약", report)
            self.assertIn("제품 영역별 분포", report)
            self.assertIn("접수 채널별 분포", report)
            self.assertIn(f"| {info['total']} | {info['high_priority']} | {info['pending']} |", report)
            self.assertNotIn("test@example.com", report)

    def test_human_correction_changes_report_without_mutating_source(self) -> None:
        source = ROOT / "output" / "openai" / "classified_voc.csv"
        log = json.loads(source.with_name("run_log.json").read_text(encoding="utf-8"))
        rows = load_results(source)
        original = render_weekly_report(rows, log)
        pending = next(row for row in rows if row["review_status"] == "PENDING")
        pending["review_status"] = "MODIFIED"
        pending["final_category"] = "REQUEST"
        pending["final_priority"] = "P2"
        updated = render_weekly_report(rows, log)

        self.assertIn("사람 검토 대기 | 사람 검토 완료", updated)
        self.assertEqual(summarize(rows)["pending"], 16)
        self.assertNotEqual(original, updated)
        self.assertEqual(load_results(source)[0]["review_status"], "PENDING")


if __name__ == "__main__":
    unittest.main()
