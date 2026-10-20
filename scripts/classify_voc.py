"""Run the Day 3 draft classifier over a VOC input CSV."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from openai_adapter import OpenAIClassifier, config_value  # noqa: E402
from voc_ops import InputError, run  # noqa: E402


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description="가상 VOC 분류 파이프라인")
    parser.add_argument("--input", type=Path, default=root / "data" / "development_voc.csv")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--engine", choices=("draft", "openai"), default="draft")
    parser.add_argument("--model", help="OpenAI 모델 ID. 미지정 시 환경 변수 또는 .env의 OPENAI_MODEL 사용")
    parser.add_argument("--max-attempts", type=int, default=2)
    args = parser.parse_args()
    try:
        predictor = OpenAIClassifier(args.model or config_value("OPENAI_MODEL")) if args.engine == "openai" else None
        output_dir = args.output_dir or root / "output" / ("openai" if args.engine == "openai" else "")
        log = run(args.input, output_dir, **({"predictor": predictor} if predictor else {}), max_attempts=args.max_attempts)
    except (InputError, OSError, ValueError) as exc:
        parser.exit(2, f"입력 처리 실패: {exc}\n")
    print(json.dumps(log, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
