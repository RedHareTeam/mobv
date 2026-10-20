"""Build a VOC Markdown summary from an existing classification run."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from reports import write_weekly_report  # noqa: E402
from review_ops import ReviewError, load_session  # noqa: E402


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description="기존 VOC 분류 결과의 운영 요약 생성")
    parser.add_argument("--source", type=Path, default=root / "output" / "openai" / "classified_voc.csv")
    parser.add_argument("--reviewed", type=Path, help="사람 검토 결과 CSV. 기본값은 분류 결과와 같은 폴더")
    parser.add_argument("--output", type=Path, help="Markdown 저장 경로. 기본값은 분류 결과와 같은 폴더")
    args = parser.parse_args()
    reviewed = args.reviewed or args.source.with_name("reviewed_voc.csv")
    output = args.output or args.source.with_name("weekly_report.md")
    try:
        rows = load_session(args.source, reviewed)
        log = json.loads(args.source.with_name("run_log.json").read_text(encoding="utf-8"))
        if log.get("run_id") != rows[0]["run_id"]:
            raise ValueError("실행 기록과 분류 결과의 실행 ID가 다릅니다")
        output.parent.mkdir(parents=True, exist_ok=True)
        write_weekly_report(output, rows, log)
    except (OSError, ValueError, ReviewError) as exc:
        parser.exit(2, f"운영 요약 생성 실패: {exc}\n")
    print(f"운영 요약 저장: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
