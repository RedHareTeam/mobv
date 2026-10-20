"""Check that the manual form shows one relevant guide before each answer."""

from __future__ import annotations

import csv
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from voc_ops import INPUT_COLUMNS


ROOT = Path(__file__).resolve().parents[1]


class ManualBaselineUITests(unittest.TestCase):
    def test_guides_appear_in_answer_order(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            source = target / "practice.csv"
            with source.open("w", encoding="utf-8", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=INPUT_COLUMNS)
                writer.writeheader()
                writer.writerow({
                    "voc_id": "PRACTICE-001", "received_at": "2026-10-20",
                    "channel": "beta_form", "platform": "web", "app_version": "unknown",
                    "screen": "login", "user_text": "연습용 문장",
                })
            result = subprocess.run(
                [sys.executable, str(ROOT / "scripts" / "manual_baseline.py"),
                 "--input", str(source), "--output-dir", str(target / "output")],
                input="\nBUG\nAUTH\nP1\nDEVELOPMENT\n\n", text=True,
                capture_output=True, check=True,
            )
            positions = [result.stdout.index(mark) for mark in (
                "유형 기준:", "유형 (", "제품 영역 기준:", "제품 영역 (",
                "우선순위 기준:", "우선순위 (", "담당 기준:", "담당 (",
            )]
            self.assertEqual(positions, sorted(positions))
            self.assertTrue((target / "output" / "manual_baseline.json").exists())


if __name__ == "__main__":
    unittest.main()
