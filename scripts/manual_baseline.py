"""Time an actual person's classification of the unseen synthetic baseline set.

This script deliberately never reads a gold-label file. Do not use its output
as evidence of a human baseline unless a person completed the prompts.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from datetime import datetime
from pathlib import Path
from time import perf_counter

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from voc_ops import AREA_BY_SCREEN, CATEGORIES, OWNERS, PRIORITIES, InputError, load_input, redact  # noqa: E402


def choose(label: str, allowed: set[str] | tuple[str, ...]) -> str:
    show_quick_guide(label)
    while True:
        value = input(f"{label} ({', '.join(sorted(allowed))}): ").strip().upper()
        if value in allowed:
            return value
        print("허용값 중 하나를 입력해 주세요.")


def show_quick_guide(label: str) -> None:
    guides = {
        "유형": "BUG=작동 실패 | USABILITY=사용 어려움 | REQUEST=새 기능 | ACCOUNT=계정·인증 | POLICY=개인정보·권한 | INFORMATION=사용법 질문 | ETC=정보 부족",
        "제품 영역": "AUTH=로그인·가입 | APPOINTMENT=약속·초대 | DATE_COORDINATION=날짜·시간 | MAP_LOCATION=지도·위치 | RECOMMENDATION=장소 추천 | VOTING=투표 | HISTORY=기록·메모 | COMMON=앱 전체·불명확",
        "우선순위": "P0=다른 사람 정보 노출 | P1=핵심 기능 차단·데이터 유실 | P2=일부 오류·우회 가능 | P3=문의·제안·경미한 불편",
        "담당": "DEVELOPMENT=기술 오류 | DESIGN_UX=화면·문구 | PRODUCT=기능 기획 | OPERATIONS=이용 안내·계정 운영 | POLICY_SECURITY=개인정보·권한 | NEEDS_TRIAGE=정보 부족",
    }
    print(f"  {label} 기준: {guides[label]}")


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description="실제 사람의 VOC 수작업 분류 시간 측정")
    parser.add_argument("--input", type=Path, default=root / "data" / "manual_baseline_v2_voc.csv")
    parser.add_argument("--output-dir", type=Path, default=root / "output")
    args = parser.parse_args()
    try:
        rows = load_input(args.input)
    except (InputError, OSError) as exc:
        parser.exit(2, f"입력 처리 실패: {exc}\n")
    print(f"가상 VOC {len(rows)}건을 수작업 분류합니다. 정답 파일은 읽지 않습니다.")
    print("각 건의 유형·제품 영역·우선순위·담당을 고르고, 어려웠던 판단을 자유롭게 적으세요.")
    print("시작 전에 docs/manual-baseline-guide.md의 짧은 분류 기준을 읽으세요. 읽는 시간은 측정하지 않습니다.")
    print("애매한 판단은 마지막 칸에 이유를 적어도 됩니다. 정확히 맞히는 시험이 아닙니다.")
    input("준비되면 Enter를 누르세요. 이때 측정을 시작합니다.")
    started = datetime.now().astimezone()
    clock = perf_counter()
    answers: list[dict[str, str]] = []
    try:
        for index, row in enumerate(rows, 1):
            item_clock = perf_counter()
            text, _ = redact(row["user_text"])
            print(f"\n[{index}/{len(rows)}] {row['voc_id']} | {row['screen']} | {text}")
            answer = {
                "voc_id": row["voc_id"],
                "category": choose("유형", CATEGORIES),
                "product_area": choose("제품 영역", set(AREA_BY_SCREEN.values())),
                "priority": choose("우선순위", PRIORITIES),
                "owner": choose("담당", OWNERS),
                "difficult_decision": input("어려웠던 판단/근거 (없으면 Enter): ").strip(),
                "elapsed_seconds": f"{perf_counter() - item_clock:.3f}",
            }
            answers.append(answer)
    except (KeyboardInterrupt, EOFError):
        print("\n측정이 중단되었습니다. 불완전한 결과는 기준선으로 저장하지 않습니다.")
        return 130
    finished = datetime.now().astimezone()
    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    csv_path = output_dir / "manual_baseline.csv"
    with csv_path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(answers[0]))
        writer.writeheader()
        writer.writerows(answers)
    summary = {
        "source": "human_manual_session", "input_file": args.input.name,
        "started_at": started.isoformat(), "finished_at": finished.isoformat(),
        "elapsed_seconds": round(perf_counter() - clock, 3),
        "completed_count": len(answers), "difficult_count": sum(bool(row["difficult_decision"]) for row in answers),
        "note": "입력 시작부터 마지막 건의 판단을 마칠 때까지 실제 경과 시간. AI 출력·정답 파일 미사용.",
    }
    (output_dir / "manual_baseline.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
