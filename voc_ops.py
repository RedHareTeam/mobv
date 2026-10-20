"""VOC pipeline for synthetic Mobv examples.

The built-in classifier is a deterministic scaffold, not an AI model. Its
predictions occupy the ai_* columns only to exercise the agreed output schema.
"""

from __future__ import annotations

import csv
import json
import re
from datetime import date, datetime
from pathlib import Path
from time import sleep
from time import perf_counter
from typing import Any, Callable


INPUT_COLUMNS = ["voc_id", "received_at", "channel", "platform", "app_version", "screen", "user_text"]
OUTPUT_COLUMNS = [
    "voc_id", "received_at", "channel", "platform", "app_version", "screen",
    "user_text_redacted", "summary", "product_area", "ai_category",
    "ai_secondary_category", "ai_priority", "ai_owner", "ai_secondary_owner",
    "ai_sla", "ai_confidence", "ai_reason", "rule_category", "rule_priority",
    "rule_owner", "rule_sla", "review_flags", "needs_review", "rule_reason",
    "review_status", "final_category", "final_priority", "final_owner",
    "final_sla", "correction_reason", "reviewed_at", "run_id",
    "prompt_version", "policy_version", "model_name", "processed_at",
    "processing_status", "error_message",
]
CHANNELS = {"beta_form", "in_app", "email", "store_review", "usability_test"}
PLATFORMS = {"android", "ios", "web", "unknown"}
SCREENS = {"login", "home", "appointment", "date_coordination", "map", "recommendation", "voting", "history", "common", "unknown"}
CATEGORIES = {"BUG", "USABILITY", "REQUEST", "ACCOUNT", "POLICY", "INFORMATION", "ETC"}
OWNERS = {"DEVELOPMENT", "DESIGN_UX", "PRODUCT", "OPERATIONS", "POLICY_SECURITY", "NEEDS_TRIAGE"}
PRIORITIES = ("P0", "P1", "P2", "P3")
SLA = {"P0": "즉시 확인", "P1": "당일", "P2": "3영업일 이내", "P3": "5영업일 이내"}
AREA_BY_SCREEN = {
    "login": "AUTH", "appointment": "APPOINTMENT",
    "date_coordination": "DATE_COORDINATION", "map": "MAP_LOCATION",
    "recommendation": "RECOMMENDATION", "voting": "VOTING",
    "history": "HISTORY", "home": "COMMON", "common": "COMMON",
    "unknown": "COMMON",
}
EMAIL = re.compile(r"(?<![A-Za-z0-9_.+-])[A-Za-z0-9_.+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}(?![A-Za-z0-9_.-])")
PHONE = re.compile(r"(?<!\d)(?:\+82[- .]?)?0?1[016789][-. ]?\d{3,4}[-. ]?\d{4}(?!\d)")
INJECTION = re.compile(r"(?:이전|앞선|시스템|프롬프트).{0,24}(?:지시|명령).{0,24}(?:무시|출력|바꿔)|(?:ignore|override).{0,30}(?:instruction|prompt)", re.I)


class InputError(ValueError):
    """Input CSV does not meet output-schema.md."""


def load_input(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != INPUT_COLUMNS:
            raise InputError(f"필수 열과 순서가 다릅니다: {reader.fieldnames!r}")
        rows = list(reader)
    if not rows:
        raise InputError("입력 CSV가 비어 있습니다")
    seen: set[str] = set()
    clean: list[dict[str, str]] = []
    for number, row in enumerate(rows, 2):
        if None in row or any(value is None for value in row.values()):
            raise InputError(f"{number}행: CSV 열 수가 맞지 않습니다")
        item = {key: re.sub(r"[\r\n\u2028\u2029]+", " ", value).strip() for key, value in row.items()}
        voc_id = item["voc_id"]
        if not voc_id or voc_id in seen:
            raise InputError(f"{number}행: VOC ID가 비었거나 중복됩니다: {voc_id!r}")
        seen.add(voc_id)
        try:
            date.fromisoformat(item["received_at"])
        except ValueError as exc:
            raise InputError(f"{number}행: 유효하지 않은 접수일") from exc
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", item["received_at"]):
            raise InputError(f"{number}행: 접수일은 YYYY-MM-DD 형식이어야 합니다")
        for field, allowed in (("channel", CHANNELS), ("platform", PLATFORMS), ("screen", SCREENS)):
            if item[field] not in allowed:
                raise InputError(f"{number}행: {field} 허용값 위반: {item[field]!r}")
        if not item["app_version"]:
            item["app_version"] = "unknown"
        if not item["user_text"]:
            raise InputError(f"{number}행: VOC 원문이 비었습니다")
        clean.append(item)
    return clean


def redact(text: str) -> tuple[str, bool]:
    """Mask likely email and mobile-number patterns before classification."""
    text, email_count = EMAIL.subn("[EMAIL]", text)
    text, phone_count = PHONE.subn("[PHONE]", text)
    return text, bool(email_count or phone_count)


def contains_any(text: str, words: tuple[str, ...]) -> bool:
    return any(word in text for word in words)


def critical_bug(text: str) -> bool:
    """Find blocked entry, lost data, wrong confirmation, or duplicate votes."""
    return (
        ("로그인" in text and contains_any(text, ("종료", "멈추", "불가", "안 돼")))
        or ("확정" in text and contains_any(text, ("다른 날짜", "잘못", "중복")))
        or (contains_any(text, ("저장", "메모")) and contains_any(text, ("사라", "없어져", "없어졌", "유실")))
        or ("투표" in text and contains_any(text, ("중복", "두 번")))
    )


def draft_prediction(item: dict[str, str], text: str) -> dict[str, str]:
    """A transparent rule draft used until a model adapter is connected."""
    area = AREA_BY_SCREEN[item["screen"]]
    if area == "COMMON":
        for word, candidate in (("지도", "MAP_LOCATION"), ("로그인", "AUTH"), ("초대", "APPOINTMENT"), ("투표", "VOTING")):
            if word in text:
                area = candidate
                break
    if "메모" in text and contains_any(text, ("사라", "없어져", "없어졌", "유실")):
        area = "HISTORY"
    ambiguous = len(text.rstrip(".!?。 ")) <= 5
    privacy = contains_any(text, ("다른 약속", "다른 사람", "권한", "보안", "개인정보", "위치 정보", "위치정보", "언제 지워", "언제 삭제"))
    exposure = contains_any(text, ("다른 약속", "다른 사람")) and contains_any(text, ("보여", "조회", "접근", "노출"))
    unauthorized = contains_any(text, ("방장이 아닌", "권한 없는", "권한이 없는")) and "확정" in text
    multi = contains_any(text, ("뿐 아니라", "도 저장되지", "도 사라졌", "에서는", "없고")) and contains_any(text, ("로그인", "메모", "지도", "추천"))
    if ambiguous:
        category, priority, reason = "ETC", "P3", "맥락이 부족해 문제를 특정하기 어려움"
    elif exposure:
        category, priority, reason = "POLICY", "P0", "다른 약속의 정보가 노출된다는 신고"
    elif unauthorized:
        category, priority, reason = "POLICY", "P1", "권한 없는 참여자의 확정 가능성"
    elif privacy:
        category, priority, reason = "POLICY", "P3", "개인정보 또는 권한 처리 기준에 관한 내용"
    elif contains_any(text, ("추가해", "수 있으면 좋", "필터", "다크 모드")):
        category, priority, reason = "REQUEST", "P3", "새 기능 또는 옵션 요청"
    elif contains_any(text, ("어떻게", "언제까지", "어디서", "어디에서", "수 있나요", "정해지나요")):
        category, priority, reason = ("ACCOUNT" if area == "AUTH" else "INFORMATION"), "P3", "사용법 또는 처리 기준 질문"
    elif contains_any(text, ("헷갈", "어려워", "설명이 없", "작아서", "표시가 없")):
        category, priority, reason = "USABILITY", "P3", "기능의 이해 또는 조작이 어려움"
    elif "인증 메일" in text and "오지 않" in text:
        category, priority, reason = "ACCOUNT", "P2", "계정 인증 절차 확인 필요"
    elif contains_any(text, ("종료", "참여가 실패", "참여할 수 없", "확정됐", "사라져", "없어져", "없어졌", "멈추", "저장되지", "중복", "두 번", "안 열", "없다고 나옵")):
        category, priority, reason = "BUG", "P1" if critical_bug(text) else "P2", "기존 기능의 실패 또는 데이터 유실 가능성"
    elif "GPS" in text and "직접" in text:
        category, priority, reason = "BUG", "P2", "위치 오차가 있으나 수동 조작 가능"
    else:
        category, priority, reason = "ETC", "P3", "초안 규칙으로 유형을 확정하지 못함"
    owner = {"BUG": "DEVELOPMENT", "USABILITY": "DESIGN_UX", "REQUEST": "PRODUCT", "ACCOUNT": "OPERATIONS", "POLICY": "POLICY_SECURITY", "INFORMATION": "OPERATIONS", "ETC": "NEEDS_TRIAGE"}[category]
    return {
        "summary": text[:80], "product_area": area, "category": category,
        "secondary_category": "BUG" if multi and category != "BUG" else "",
        "priority": priority, "owner": owner, "secondary_owner": "DEVELOPMENT" if multi and owner != "DEVELOPMENT" else "",
        "sla": SLA[priority], "confidence": "LOW" if ambiguous or multi or category == "ETC" else "MEDIUM",
        "reason": reason,
    }


def apply_rules(item: dict[str, str], text: str, personal_data: bool, prediction: dict[str, str]) -> tuple[dict[str, str], list[str], str]:
    category, priority, owner = prediction["category"], prediction["priority"], prediction["owner"]
    flags: list[str] = []
    reasons: list[str] = []
    privacy = contains_any(text, ("다른 약속", "다른 사람", "개인정보", "위치 정보", "위치정보", "권한", "보안", "언제 지워", "언제 삭제"))
    exposure = contains_any(text, ("다른 약속", "다른 사람")) and contains_any(text, ("보여", "조회", "접근", "노출"))
    unauthorized = contains_any(text, ("방장이 아닌", "권한 없는", "권한이 없는")) and "확정" in text
    privacy = privacy or unauthorized
    if privacy:
        flags.append("PRIVACY_SECURITY")
        minimum = "P0" if exposure else "P1" if unauthorized else None
        if minimum and PRIORITIES.index(priority) > PRIORITIES.index(minimum):
            priority = minimum
            reasons.append(f"개인정보 노출·권한 오류 최소 {minimum} 적용")
        if owner != "POLICY_SECURITY":
            owner = "POLICY_SECURITY"
            reasons.append("정책·보안 담당으로 보정")
    if unauthorized and PRIORITIES.index(priority) > 1:
        priority = "P1"
        reasons.append("권한 없는 확정은 최소 P1")
    if category == "BUG" and critical_bug(text) and PRIORITIES.index(priority) > 1:
        priority = "P1"
        reasons.append("핵심 흐름 차단·데이터 유실은 최소 P1")
    if priority in {"P0", "P1"}:
        flags.insert(0, "HIGH_PRIORITY")
    if contains_any(text, ("뿐 아니라", "도 저장되지", "도 사라졌")):
        flags.append("MULTI_ISSUE")
    if len(text.rstrip(".!?。 ")) <= 5:
        flags.append("AMBIGUOUS")
    if prediction["confidence"] == "LOW":
        flags.append("LOW_CONFIDENCE")
    if personal_data:
        flags.append("PERSONAL_DATA")
    if INJECTION.search(text):
        flags.append("PROMPT_INJECTION")
    if priority != prediction["priority"] or owner != prediction["owner"]:
        flags.append("RULE_OVERRIDE")
    return {"category": category, "priority": priority, "owner": owner, "sla": SLA[priority]}, flags, "; ".join(reasons) or "AI 초안 유지"


def classify(
    item: dict[str, str], run_id: str, processed_at: str,
    predictor: Callable[[dict[str, str], str], dict[str, str]] = draft_prediction,
    *, model_name: str = "heuristic-draft-v0", prompt_version: str = "not-applicable",
) -> dict[str, str]:
    redacted, personal_data = redact(item["user_text"])
    prediction = predictor(item, redacted)
    rule, flags, rule_reason = apply_rules(item, redacted, personal_data, prediction)
    review = bool(flags) or rule["owner"] == "NEEDS_TRIAGE" or rule["category"] == "ETC"
    result = {
        **{field: item[field] for field in INPUT_COLUMNS if field != "user_text"},
        "user_text_redacted": redacted, "summary": prediction["summary"],
        "product_area": prediction["product_area"],
        **{f"ai_{field}": prediction[field] for field in ("category", "secondary_category", "priority", "owner", "secondary_owner", "sla", "confidence", "reason")},
        **{f"rule_{field}": rule[field] for field in ("category", "priority", "owner", "sla")},
        "review_flags": "|".join(flags), "needs_review": str(review).lower(),
        "rule_reason": rule_reason, "review_status": "PENDING" if review else "APPROVED",
        **{f"final_{field}": "" if review else rule[field] for field in ("category", "priority", "owner", "sla")},
        "correction_reason": "", "reviewed_at": "", "run_id": run_id,
        "prompt_version": prompt_version, "policy_version": "v1.0",
        "model_name": model_name, "processed_at": processed_at,
        "processing_status": "SUCCESS", "error_message": "",
    }
    assert set(result) == set(OUTPUT_COLUMNS)
    return result


def failed_result(
    item: dict[str, str], run_id: str, processed_at: str,
    model_name: str, prompt_version: str, error: str,
) -> dict[str, str]:
    redacted, _ = redact(item["user_text"])
    result = {field: "" for field in OUTPUT_COLUMNS}
    result.update({field: item[field] for field in INPUT_COLUMNS if field != "user_text"})
    result.update({
        "user_text_redacted": redacted, "review_flags": "INVALID_OUTPUT",
        "needs_review": "true", "rule_reason": "분류 실패로 사람 검토 필요",
        "review_status": "PENDING", "run_id": run_id,
        "prompt_version": prompt_version, "policy_version": "v1.0",
        "model_name": model_name, "processed_at": processed_at,
        "processing_status": "FAILED", "error_message": error,
    })
    return result


def write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=OUTPUT_COLUMNS)
        writer.writeheader()
        writer.writerows(rows)


def run(
    input_path: Path, output_dir: Path,
    predictor: Callable[[dict[str, str], str], dict[str, str]] = draft_prediction,
    *, max_attempts: int = 2, retry_delay: float = 0.5,
) -> dict[str, Any]:
    # Validate every row before writing anything. The original file is never changed.
    if max_attempts < 1:
        raise ValueError("max_attempts는 1 이상이어야 합니다")
    from openai_adapter import ModelError

    started = datetime.now().astimezone()
    clock = perf_counter()
    items = load_input(input_path)
    run_id = started.strftime("RUN-%Y%m%d-%H%M%S-%f")
    model_name = getattr(predictor, "model_name", "heuristic-draft-v0")
    prompt_version = getattr(predictor, "prompt_version", "not-applicable")
    rows: list[dict[str, str]] = []
    errors: list[dict[str, str]] = []
    for item in items:
        for attempt in range(1, max_attempts + 1):
            try:
                row = classify(
                    item, run_id, datetime.now().astimezone().isoformat(), predictor,
                    model_name=model_name, prompt_version=prompt_version,
                )
                break
            except ModelError as exc:
                if exc.retryable and attempt < max_attempts:
                    sleep(retry_delay * attempt)
                    continue
                message = f"{exc} (attempts={attempt})"
                row = failed_result(
                    item, run_id, datetime.now().astimezone().isoformat(),
                    model_name, prompt_version, message,
                )
                errors.append({"voc_id": item["voc_id"], "error": message})
                break
        rows.append(row)
    output_dir.mkdir(parents=True, exist_ok=True)
    write_csv(output_dir / "classified_voc.csv", rows)
    write_csv(output_dir / "review_queue.csv", [row for row in rows if row["needs_review"] == "true"])
    finished = datetime.now().astimezone()
    log: dict[str, Any] = {
        "run_id": run_id, "started_at": started.isoformat(), "finished_at": finished.isoformat(),
        "input_file": input_path.name, "input_count": len(items),
        "success_count": len(rows) - len(errors), "failure_count": len(errors),
        "review_count": sum(row["needs_review"] == "true" for row in rows),
        "rule_override_count": sum("RULE_OVERRIDE" in row["review_flags"].split("|") for row in rows),
        "prompt_version": prompt_version, "policy_version": "v1.0",
        "model_name": model_name, "elapsed_seconds": round(perf_counter() - clock, 3),
        "errors": errors,
    }
    (output_dir / "run_log.json").write_text(json.dumps(log, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return log
