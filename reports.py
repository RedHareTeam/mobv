"""Operational summaries for one classified VOC run."""

from __future__ import annotations

import re
from collections import Counter
from html import escape
from pathlib import Path
from typing import Any


CATEGORY_NAMES = {
    "ACCOUNT": "계정", "BUG": "오류", "ETC": "기타", "INFORMATION": "이용 문의",
    "POLICY": "정책·보안", "REQUEST": "기능 요청", "USABILITY": "사용성",
}
PRIORITIES = ("P0", "P1", "P2", "P3")
AREA_NAMES = {
    "APPOINTMENT": "약속", "AUTH": "로그인·계정", "COMMON": "공통",
    "DATE_COORDINATION": "날짜 조율", "HISTORY": "기록", "MAP_LOCATION": "지도·위치",
    "RECOMMENDATION": "장소 추천", "VOTING": "투표",
}
CHANNEL_NAMES = {
    "beta_form": "베타 피드백", "in_app": "앱 내", "email": "이메일",
    "store_review": "스토어 리뷰", "usability_test": "사용성 테스트",
}


def current_value(row: dict[str, str], field: str) -> str:
    """Use a saved human decision when present, otherwise the rule result."""
    if row["review_status"] != "PENDING" and row[f"final_{field}"]:
        return row[f"final_{field}"]
    return row[f"rule_{field}"]


def summarize(rows: list[dict[str, str]]) -> dict[str, Any]:
    categories = Counter(current_value(row, "category") or "UNCLASSIFIED" for row in rows)
    priorities = Counter(current_value(row, "priority") or "UNCLASSIFIED" for row in rows)
    by_date = Counter(row["received_at"] for row in rows)
    areas = Counter(row["product_area"] or "UNCLASSIFIED" for row in rows)
    channels = Counter(row["channel"] or "UNCLASSIFIED" for row in rows)
    area_urgent = Counter(row["product_area"] or "UNCLASSIFIED" for row in rows
                          if current_value(row, "priority") in {"P0", "P1"})
    urgent = sorted(
        (row for row in rows if current_value(row, "priority") in {"P0", "P1"}),
        key=lambda row: (PRIORITIES.index(current_value(row, "priority")), row["received_at"], row["voc_id"]),
    )
    return {
        "total": len(rows),
        "pending": sum(row["review_status"] == "PENDING" for row in rows),
        "reviewed": sum(row["needs_review"] == "true" and row["review_status"] != "PENDING" for row in rows),
        "failed": sum(row["processing_status"] == "FAILED" for row in rows),
        "high_priority": len(urgent),
        "categories": categories,
        "priorities": priorities,
        "by_date": by_date,
        "areas": areas,
        "channels": channels,
        "area_urgent": area_urgent,
        "urgent": urgent,
        "first_date": min((row["received_at"] for row in rows), default=""),
        "last_date": max((row["received_at"] for row in rows), default=""),
    }


def _cell(value: str) -> str:
    """Keep model-written summaries inside one Markdown table cell."""
    return escape(re.sub(r"\s+", " ", value).strip()).replace("|", "¦") or "—"


def render_weekly_report(rows: list[dict[str, str]], log: dict[str, Any]) -> str:
    info = summarize(rows)
    period = info["first_date"]
    if info["last_date"] != period:
        period += f" ~ {info['last_date']}"
    lines = [
        "# Mobv VOC 운영 요약",
        "",
        f"- 입력 기간: {period or '확인 필요'}",
        f"- 실행 ID: `{_cell(str(log.get('run_id', '확인 필요')))}`",
        f"- 분류 방식: `{_cell(str(log.get('model_name', '확인 필요')))}`",
        "",
        "이 문서는 입력 CSV 전체의 요약입니다. 입력 기간이 여러 주에 걸치면 주별 수치로 나누지 않습니다.",
        "사람 검토가 남은 항목의 분류는 운영 기준을 적용한 잠정 결과입니다.",
        "",
        "## 처리 현황",
        "",
        "| 전체 | 즉시·당일 확인 (P0·P1) | 사람 검토 대기 | 사람 검토 완료 | 분류 실패 |",
        "| ---: | ---: | ---: | ---: | ---: |",
        f"| {info['total']} | {info['high_priority']} | {info['pending']} | {info['reviewed']} | {info['failed']} |",
        "",
        "## 우선 확인할 의견",
        "",
        "| ID | 우선순위 | 유형 | 요약 | 검토 상태 |",
        "| --- | --- | --- | --- | --- |",
    ]
    if info["urgent"]:
        for row in info["urgent"]:
            category = current_value(row, "category")
            lines.append(
                f"| {_cell(row['voc_id'])} | {_cell(current_value(row, 'priority'))} "
                f"| {_cell(CATEGORY_NAMES.get(category, category))} | {_cell(row['summary'])} "
                f"| {_cell(row['review_status'])} |"
            )
    else:
        lines.append("| — | — | — | 즉시·당일 확인 대상 없음 | — |")
    lines += ["", "## 유형별 분포", "", "| 유형 | 건수 |", "| --- | ---: |"]
    for category, count in sorted(info["categories"].items(), key=lambda item: (-item[1], item[0])):
        lines.append(f"| {_cell(CATEGORY_NAMES.get(category, category))} | {count} |")
    lines += ["", "## 우선순위별 분포", "", "| 우선순위 | 건수 |", "| --- | ---: |"]
    for priority in (*PRIORITIES, "UNCLASSIFIED"):
        if info["priorities"][priority]:
            lines.append(f"| {_cell(priority)} | {info['priorities'][priority]} |")
    lines += ["", "## 접수일별 건수", "", "| 접수일 | 건수 |", "| --- | ---: |"]
    for day, count in sorted(info["by_date"].items()):
        lines.append(f"| {_cell(day)} | {count} |")
    lines += ["", "## 제품 영역별 분포", "", "| 제품 영역 | 전체 | P0·P1 |",
              "| --- | ---: | ---: |"]
    for area, count in sorted(info["areas"].items(), key=lambda item: (-item[1], item[0])):
        lines.append(f"| {_cell(AREA_NAMES.get(area, area))} | {count} | {info['area_urgent'][area]} |")
    lines += ["", "## 접수 채널별 분포", "", "| 채널 | 건수 |", "| --- | ---: |"]
    for channel, count in sorted(info["channels"].items(), key=lambda item: (-item[1], item[0])):
        lines.append(f"| {_cell(CHANNEL_NAMES.get(channel, channel))} | {count} |")
    lines += [
        "", "## 다음 확인", "",
        f"- 사람 검토 대기 {info['pending']}건은 운영자가 승인하거나 수정해야 최종 판단이 됩니다.",
        "- 분류 실패 건은 오류 원인을 확인한 뒤 사람 검토 또는 재실행이 필요합니다."
        if info["failed"] else "- 분류 실패 건은 없습니다.",
        "- 이 수치는 가상 VOC의 처리 현황이며 정확도나 실제 고객 영향도를 뜻하지 않습니다.",
        "- 접수 추이와 분포는 이 CSV 한 묶음 기준이며 실제 운영 추세를 뜻하지 않습니다.",
        "",
    ]
    return "\n".join(lines)


def write_weekly_report(path: Path, rows: list[dict[str, str]], log: dict[str, Any]) -> None:
    path.write_text(render_weekly_report(rows, log), encoding="utf-8")
