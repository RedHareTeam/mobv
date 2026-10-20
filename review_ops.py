"""Human review of classified synthetic VOC results.

Keep model and rule decisions intact; write a separate reviewed_voc.csv with
human final fields so the original classified_voc.csv remains auditable.
"""

from __future__ import annotations

import csv
import os
import tempfile
from datetime import datetime
from pathlib import Path

from voc_ops import CATEGORIES, OUTPUT_COLUMNS, OWNERS, SLA


class ReviewError(ValueError):
    """Review source or decision is invalid."""


def load_results(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != OUTPUT_COLUMNS:
            raise ReviewError("분류 결과의 열과 순서가 출력 스키마와 다릅니다")
        rows = list(reader)
    if not rows:
        raise ReviewError("분류 결과가 비었습니다")
    seen: set[str] = set()
    run_ids: set[str] = set()
    for index, row in enumerate(rows, 2):
        if None in row or any(value is None for value in row.values()):
            raise ReviewError(f"{index}행: CSV 열 수가 맞지 않습니다")
        voc_id = row["voc_id"]
        if not voc_id or voc_id in seen:
            raise ReviewError(f"{index}행: VOC ID가 비었거나 중복됩니다")
        seen.add(voc_id)
        run_ids.add(row["run_id"])
        if row["review_status"] not in {"PENDING", "APPROVED", "MODIFIED"}:
            raise ReviewError(f"{index}행: 검토 상태가 올바르지 않습니다")
    if len(run_ids) != 1 or not next(iter(run_ids)):
        raise ReviewError("한 실행의 결과만 검토할 수 있습니다")
    return rows


def load_session(source: Path, target: Path) -> list[dict[str, str]]:
    """Resume a saved review only when it matches the current classified run."""
    source_rows = load_results(source)
    if not target.exists():
        return source_rows
    saved_rows = load_results(target)
    if ([row["voc_id"] for row in source_rows] != [row["voc_id"] for row in saved_rows]
            or source_rows[0]["run_id"] != saved_rows[0]["run_id"]):
        raise ReviewError("기존 검토 파일이 현재 분류 실행과 다릅니다. 별도 출력 경로를 지정하세요")
    # Only human-owned fields may differ from the original classifier output.
    human_fields = {"review_status", "final_category", "final_priority", "final_owner",
                    "final_sla", "correction_reason", "reviewed_at"}
    for original, saved in zip(source_rows, saved_rows):
        if any(original[field] != saved[field] for field in OUTPUT_COLUMNS if field not in human_fields):
            raise ReviewError("기존 검토 파일의 AI·규칙·입력 필드가 원본과 다릅니다")
    return saved_rows


def pending_rows(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    return [row for row in rows if row["review_status"] == "PENDING"]


def apply_decision(
    row: dict[str, str], *, category: str | None = None,
    priority: str | None = None, owner: str | None = None,
    reason: str = "", reviewed_at: str | None = None,
) -> dict[str, str]:
    """Approve unchanged rule values, or save a reasoned human correction."""
    if row["review_status"] != "PENDING" or row["needs_review"] != "true":
        raise ReviewError("대기 중인 검토 대상만 승인·수정할 수 있습니다")
    category = category or row["rule_category"]
    priority = priority or row["rule_priority"]
    owner = owner or row["rule_owner"]
    if category not in CATEGORIES or priority not in SLA or owner not in OWNERS:
        raise ReviewError("최종 유형·우선순위·담당에 허용되지 않은 값이 있습니다")
    changed = any((category != row["rule_category"], priority != row["rule_priority"],
                   owner != row["rule_owner"]))
    if row["processing_status"] == "FAILED" and not changed:
        raise ReviewError("AI 분류 실패 건은 규칙 결과가 없어 그대로 승인할 수 없습니다")
    reason = reason.strip()
    if changed and not reason:
        raise ReviewError("수정한 경우 수정 이유를 입력해야 합니다")
    if not changed and reason:
        raise ReviewError("규칙 결과를 그대로 승인할 때는 수정 이유를 비워 주세요")
    result = row.copy()
    result.update({
        "review_status": "MODIFIED" if changed else "APPROVED",
        "final_category": category, "final_priority": priority,
        "final_owner": owner, "final_sla": SLA[priority],
        "correction_reason": reason,
        "reviewed_at": reviewed_at or datetime.now().astimezone().isoformat(),
    })
    return result


def save_results(path: Path, rows: list[dict[str, str]]) -> None:
    """Write a complete review snapshot without truncating an earlier save."""
    if not rows or any(set(row) != set(OUTPUT_COLUMNS) for row in rows):
        raise ReviewError("검토 결과의 열이 출력 스키마와 다릅니다")
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8-sig", newline="", suffix=".tmp",
                                         prefix="review-", dir=path.parent, delete=False) as handle:
            temp_path = Path(handle.name)
            writer = csv.DictWriter(handle, fieldnames=OUTPUT_COLUMNS)
            writer.writeheader()
            writer.writerows(rows)
        os.replace(temp_path, path)
    finally:
        if temp_path is not None and temp_path.exists():
            temp_path.unlink()
