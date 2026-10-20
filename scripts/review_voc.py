"""Review pending synthetic VOC classifications one by one."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from review_ops import ReviewError, apply_decision, load_session, pending_rows, save_results  # noqa: E402
from voc_ops import CATEGORIES, OWNERS, SLA  # noqa: E402


def choose(label: str, allowed: set[str], default: str = "") -> str:
    while True:
        suffix = f" [{default}]" if default else ""
        value = input(f"{label} ({', '.join(sorted(allowed))}){suffix}: ").strip().upper()
        value = value or default
        if value in allowed:
            return value
        print("허용값 중 하나를 입력해 주세요.")


def show(row: dict[str, str], index: int, total: int) -> None:
    print(f"\n[{index}/{total}] {row['voc_id']} | {row['screen']}")
    print(f"VOC: {row['user_text_redacted']}")
    print(f"AI: {row['ai_category']} / {row['ai_priority']} / {row['ai_owner']} | {row['ai_reason']}")
    print(f"규칙: {row['rule_category']} / {row['rule_priority']} / {row['rule_owner']}")
    print(f"검토 표시: {row['review_flags'] or '-'} | {row['rule_reason']}")
    if row["processing_status"] == "FAILED":
        print(f"분류 실패: {row['error_message']}")


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description="가상 VOC 사람 검토 기록")
    parser.add_argument("--source", type=Path, default=root / "output" / "openai" / "classified_voc.csv")
    parser.add_argument("--output", type=Path, default=root / "output" / "openai" / "reviewed_voc.csv")
    args = parser.parse_args()
    if args.source.resolve() == args.output.resolve():
        parser.exit(2, "원본 분류 결과와 검토 저장 경로는 달라야 합니다\n")
    try:
        rows = load_session(args.source, args.output)
    except (OSError, ReviewError) as exc:
        parser.exit(2, f"검토 시작 실패: {exc}\n")
    todo = pending_rows(rows)
    print(f"검토 대기 {len(todo)}건 / 전체 {len(rows)}건. 항목마다 저장하므로 중단 후 재개할 수 있습니다.")
    if not todo:
        return 0
    by_id = {row["voc_id"]: index for index, row in enumerate(rows)}
    try:
        for number, row in enumerate(todo, 1):
            while True:
                show(row, number, len(todo))
                choice = input("그대로 승인(a), 수정(m), 건너뛰기(s), 종료(q): ").strip().lower()
                if choice == "q":
                    return 0
                if choice == "s":
                    break
                if choice not in {"a", "m"}:
                    print("a, m, s, q 중 하나를 입력해 주세요.")
                    continue
                if choice == "a":
                    try:
                        updated = apply_decision(row)
                    except ReviewError as exc:
                        print(f"저장 불가: {exc}")
                        continue
                else:
                    category = choose("최종 유형", CATEGORIES, row["rule_category"])
                    priority = choose("최종 우선순위", set(SLA), row["rule_priority"])
                    owner = choose("최종 담당", OWNERS, row["rule_owner"])
                    reason = input("수정 이유: ").strip()
                    try:
                        updated = apply_decision(row, category=category, priority=priority,
                                                 owner=owner, reason=reason)
                    except ReviewError as exc:
                        print(f"저장 불가: {exc}")
                        continue
                rows[by_id[row["voc_id"]]] = updated
                save_results(args.output, rows)
                print(f"저장 완료: {row['voc_id']} ({updated['review_status']})")
                break
    except (KeyboardInterrupt, EOFError):
        print("\n검토를 중단했습니다. 이미 저장한 항목은 다음 실행에서 이어집니다.")
        return 0
    print(f"검토 대기 {len(pending_rows(rows))}건. 저장 파일: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
