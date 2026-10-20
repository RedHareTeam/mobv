"""Local review dashboard for synthetic Mobv VOC classifications."""

from __future__ import annotations

import json
import tempfile
from datetime import datetime
from html import escape
from pathlib import Path
from uuid import uuid4

import streamlit as st

from openai_adapter import OpenAIClassifier, config_value
from reports import current_value, render_weekly_report, summarize
from review_ops import ReviewError, apply_decision, load_session, pending_rows, save_results
from voc_ops import CATEGORIES, OWNERS, SLA, InputError, load_input, run


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "output" / "openai" / "classified_voc.csv"
REVIEWED = ROOT / "output" / "openai" / "reviewed_voc.csv"
BATCHES = ROOT / "output" / "batches"
MAX_UPLOAD_BYTES = 1_000_000
MAX_UPLOAD_ROWS = 100
PRIORITY_ORDER = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}
CATEGORY_LABELS = {
    "ACCOUNT": "계정", "BUG": "오류", "ETC": "기타", "INFORMATION": "이용 문의",
    "POLICY": "정책·보안", "REQUEST": "기능 요청", "USABILITY": "사용성",
}
OWNER_LABELS = {
    "DESIGN_UX": "디자인·UX", "DEVELOPMENT": "개발", "NEEDS_TRIAGE": "담당 확인 필요",
    "OPERATIONS": "운영", "POLICY_SECURITY": "정책·보안", "PRODUCT": "제품",
}
AREA_LABELS = {
    "APPOINTMENT": "약속", "AUTH": "로그인·계정", "COMMON": "공통",
    "DATE_COORDINATION": "날짜 조율", "HISTORY": "기록", "MAP_LOCATION": "지도·위치",
    "RECOMMENDATION": "장소 추천", "VOTING": "투표",
}
CHANNEL_LABELS = {
    "beta_form": "베타 피드백", "in_app": "앱 내", "email": "이메일",
    "store_review": "스토어 리뷰", "usability_test": "사용성 테스트",
}
PLATFORM_LABELS = {"android": "Android", "ios": "iOS", "web": "웹", "unknown": "플랫폼 미상"}
FLAG_LABELS = {
    "HIGH_PRIORITY": "높은 우선순위", "PRIVACY_SECURITY": "개인정보·보안",
    "LOW_CONFIDENCE": "낮은 확신도", "CATEGORY_CONFLICT": "유형 불일치",
    "PRIORITY_CONFLICT": "우선순위 불일치", "OWNER_CONFLICT": "담당 불일치",
    "MODEL_ERROR": "분류 오류", "PROCESSING_FAILED": "처리 실패",
    "AMBIGUOUS": "내용이 모호함", "MULTI_ISSUE": "여러 문제 포함",
    "PERSONAL_DATA": "개인정보 포함", "PROMPT_INJECTION": "지시문 포함",
    "RULE_OVERRIDE": "운영 기준에 따라 변경됨",
    "INVALID_OUTPUT": "AI 분류 실패",
}


def display(value: str, labels: dict[str, str]) -> str:
    return labels.get(value, value or "미정")


def display_flags(flags: str) -> str:
    return " · ".join(display(flag, FLAG_LABELS) for flag in flags.split("|") if flag) or "추가 확인 사항 없음"


def display_priority(value: str) -> str:
    return f"{value} · {SLA[value]}" if value in SLA else "확인 필요"


def queue_title(row: dict[str, str]) -> str:
    title = (row["summary"] or row["user_text_redacted"]).strip()
    return f"{title[:63]}…" if len(title) > 64 else title


def comparison_row(label: str, draft: str, result: str, changed: bool) -> str:
    marker = '<span class="change-marker">변경</span>' if changed else ""
    row_class = ' class="changed"' if changed else ""
    return (f'<tr{row_class}><th scope="row">{escape(label)}</th>'
            f'<td>{escape(draft)}</td><td>{escape(result)}{marker}</td></tr>')


def select_value(label: str, values: set[str], current: str,
                 labels: dict[str, str] | None = None) -> str | None:
    options = sorted(values)
    return st.selectbox(label, options, index=options.index(current) if current in options else None,
                        format_func=lambda value: display(value, labels or {}))


def save_decision(rows: list[dict[str, str]], row: dict[str, str],
                  reviewed_path: Path, **changes: str) -> None:
    updated = apply_decision(row, **changes)
    index = next(index for index, item in enumerate(rows) if item["voc_id"] == row["voc_id"])
    rows[index] = updated
    save_results(reviewed_path, rows)
    st.session_state["last_saved"] = f"{row['voc_id']} 처리 완료"
    st.rerun()


def render_review(source: Path, reviewed_path: Path) -> None:
    if not source.exists():
        st.info("분류 결과가 없습니다. CSV 가져오기에서 새 작업을 시작하세요.")
        st.stop()
    try:
        rows = load_session(source, reviewed_path)
    except (OSError, ReviewError) as exc:
        st.error(f"분류 결과를 열 수 없습니다: {exc}")
        st.stop()

    pending = sorted(pending_rows(rows), key=lambda row: PRIORITY_ORDER.get(row["rule_priority"], 4))
    approved = sum(row["review_status"] == "APPROVED" and row["needs_review"] == "true" for row in rows)
    modified = sum(row["review_status"] == "MODIFIED" for row in rows)
    st.html(f"""
        <section class="work-status" aria-label="현재 작업 현황">
          <strong>확인할 의견 {len(pending)}건</strong>
          <span>전체 {len(rows)}건</span>
          <span>직접 승인 {approved}건</span>
          <span>직접 수정 {modified}건</span>
        </section>
    """)
    if "last_saved" in st.session_state:
        st.success(st.session_state.pop("last_saved"))

    if not pending:
        st.success("확인할 의견을 모두 처리했습니다.")
        if reviewed_path.exists():
            st.download_button("검토 결과 CSV 다운로드", reviewed_path.read_bytes(),
                               file_name="reviewed_voc.csv", mime="text/csv")
        return

    queue_col, detail_col = st.columns([1, 1.65], gap="small")
    with queue_col:
        with st.container(border=True, key="queue_panel"):
            st.markdown("## 의견 목록")
            st.caption("우선순위가 높은 순")
            queue_by_id = {item["voc_id"]: item for item in pending}
            if st.session_state.get("selected_voc") not in queue_by_id:
                st.session_state["selected_voc"] = pending[0]["voc_id"]
            with st.container(height=464, border=False, key="queue_list"):
                selected_id = st.radio(
                    "검토할 의견", list(queue_by_id), label_visibility="collapsed",
                    format_func=lambda voc_id: queue_title(queue_by_id[voc_id]),
                    captions=[f"**{display_priority(item['rule_priority'])}** · {item['voc_id']} · "
                              f"{display(item['rule_category'], CATEGORY_LABELS)}"
                              for item in pending],
                    key="selected_voc",
                    width="stretch",
                )

    row = next(row for row in pending if row["voc_id"] == selected_id)
    with detail_col:
        with st.container(border=True, key="detail_panel"):
            priority = row["rule_priority"] or "우선순위 미정"
            priority_class = "urgent" if priority in {"P0", "P1"} else "normal"
            st.html(f"""
              <section class="feedback-section" aria-labelledby="feedback-title">
                <div class="detail-heading">
                  <h2 class="panel-title" id="feedback-title">고객 의견</h2>
                  <span class="priority-tag {priority_class}">{escape(display_priority(priority))}</span>
                </div>
                <div class="customer-message">
                  <p>{escape(row['user_text_redacted'])}</p>
                </div>
                <div class="detail-meta">
                  <span class="detail-id">접수 ID {escape(row['voc_id'])}</span>
                  <span>접수일 {escape(row['received_at'])}</span>
                  <span>{escape(display(row['channel'], CHANNEL_LABELS))} ·
                    {escape(display(row['platform'], PLATFORM_LABELS))}</span>
                </div>
                <dl class="detail-facts">
                  <div><dt>제품 영역</dt><dd>{escape(display(row['product_area'], AREA_LABELS))}</dd></div>
                  <div><dt>확인 이유</dt><dd>{escape(display_flags(row['review_flags']))}</dd></div>
                </dl>
              </section>
            """)
            draft_title = "규칙 초안" if row["model_name"] == "heuristic-draft-v0" else "AI 분류 초안"
            rule_reason = ("추가 변경 없음" if row["rule_reason"] == "AI 초안 유지"
                           else row["rule_reason"])
            changed_fields = [label for label, field in (
                ("유형", "category"), ("우선순위", "priority"), ("담당", "owner"),
            ) if row[f"ai_{field}"] and row[f"ai_{field}"] != row[f"rule_{field}"]]
            if row["processing_status"] == "FAILED":
                comparison_status = "자동 분류 실패"
                comparison_status_class = "failed"
            elif changed_fields:
                comparison_status = f"{'·'.join(changed_fields)} 변경"
                comparison_status_class = "changed"
            else:
                comparison_status = "초안과 동일"
                comparison_status_class = "unchanged"
            category_row = comparison_row(
                "유형", display(row["ai_category"], CATEGORY_LABELS),
                display(row["rule_category"], CATEGORY_LABELS),
                bool(row["ai_category"] and row["ai_category"] != row["rule_category"]),
            )
            priority_row = comparison_row(
                "우선순위", display_priority(row["ai_priority"]),
                display_priority(row["rule_priority"]),
                bool(row["ai_priority"] and row["ai_priority"] != row["rule_priority"]),
            )
            owner_row = comparison_row(
                "담당", display(row["ai_owner"], OWNER_LABELS),
                display(row["rule_owner"], OWNER_LABELS),
                bool(row["ai_owner"] and row["ai_owner"] != row["rule_owner"]),
            )
            st.html(f"""
                <section class="classification-section" aria-labelledby="classification-title">
                  <div class="classification-heading">
                    <h2 id="classification-title">분류 결과 비교</h2>
                    <span class="comparison-status {comparison_status_class}">{escape(comparison_status)}</span>
                  </div>
                  <p class="classification-help">왼쪽은 처음 제안한 값, 오른쪽은 운영 기준을 적용한 값입니다. 승인 전에는 확정되지 않습니다.</p>
                  <div class="comparison-scroll">
                    <table class="comparison-table">
                      <thead><tr><th scope="col">항목</th><th scope="col">{escape(draft_title)}</th><th scope="col">운영 기준 적용 후</th></tr></thead>
                      <tbody>
                        {category_row}
                        {priority_row}
                        {owner_row}
                      </tbody>
                    </table>
                  </div>
                  <div class="comparison-reasons">
                    <div><strong>첫 분류 이유</strong><p>{escape(row['ai_reason'] or row['error_message'] or '기록된 근거 없음')}</p></div>
                    <div><strong>기준 적용 이유</strong><p>{escape(rule_reason or '기록된 이유 없음')}</p></div>
                  </div>
                </section>
            """)
            st.divider()
            st.markdown("### 최종 결정")
            failed = row["processing_status"] == "FAILED"
            if failed:
                st.warning("자동 분류에 실패했습니다. 유형·우선순위·담당을 확인해 저장하세요.")
            else:
                st.caption("승인하면 바로 저장되고 이 목록에서 빠집니다.")
            if not failed and st.button("운영 기준 결과 승인", type="primary"):
                try:
                    save_decision(rows, row, reviewed_path)
                except (ReviewError, OSError) as exc:
                    st.error(f"승인 결과를 저장하지 못했습니다: {exc}")

            with st.expander("분류 수정", expanded=failed):
                with st.form(f"modify-{selected_id}", enter_to_submit=False, border=False):
                    category_col, priority_col = st.columns(2)
                    with category_col:
                        category = select_value("유형", CATEGORIES, row["rule_category"], CATEGORY_LABELS)
                    with priority_col:
                        priority = select_value("우선순위", set(SLA), row["rule_priority"])
                    owner = select_value("담당", OWNERS, row["rule_owner"], OWNER_LABELS)
                    reason = st.text_area("수정 이유", placeholder="변경한 내용과 판단 근거를 적어주세요.")
                    submitted = st.form_submit_button("수정 내용 저장", use_container_width=True)
            if submitted:
                try:
                    save_decision(rows, row, reviewed_path, category=category or "", priority=priority or "",
                                  owner=owner or "", reason=reason)
                except (ReviewError, OSError) as exc:
                    st.error(f"수정 결과를 저장하지 못했습니다: {exc}")

    if reviewed_path.exists():
        st.download_button("검토 결과 CSV 다운로드", reviewed_path.read_bytes(),
                           file_name="reviewed_voc.csv", mime="text/csv")


def available_batches() -> dict[str, tuple[Path, Path]]:
    batches = {"development": (SOURCE, REVIEWED)}
    if BATCHES.exists():
        for source in sorted(BATCHES.glob("*/classified_voc.csv"), reverse=True):
            batches[source.parent.name] = (source, source.with_name("reviewed_voc.csv"))
    return batches


def batch_label(batch_id: str) -> str:
    return "개발용 예시 VOC" if batch_id == "development" else f"CSV 업로드 · {batch_id}"


def display_time(value: str) -> str:
    if not isinstance(value, str):
        return ""
    try:
        return datetime.fromisoformat(value).strftime("%Y.%m.%d %H:%M")
    except ValueError:
        return value


def distribution_html(counts: dict[str, int], codes: list[str], labels: dict[str, str]) -> str:
    largest = max((counts.get(code, 0) for code in codes), default=1) or 1
    rows = []
    for code in codes:
        count = counts.get(code, 0)
        width = 100 * count / largest
        tone = "urgent" if code in {"P0", "P1"} else "normal"
        rows.append(
            f'<div class="distribution-row"><span class="distribution-label">{escape(display(code, labels))}</span>'
            f'<div class="distribution-track" aria-hidden="true">'
            f'<span class="distribution-fill {tone}" style="width:{width:.1f}%"></span></div>'
            f'<strong class="distribution-count">{count}건</strong></div>'
        )
    return '<div class="distribution-list">' + "".join(rows) + "</div>"


def render_overview(source: Path, reviewed_path: Path) -> None:
    if not source.exists():
        st.info("분류 결과가 없습니다. CSV 가져오기에서 새 작업을 시작하세요.")
        return
    try:
        rows = load_session(source, reviewed_path)
    except (OSError, ReviewError) as exc:
        st.error(f"분류 결과를 열 수 없습니다: {exc}")
        return
    info = summarize(rows)
    st.html(f"""
      <section class="overview-summary" aria-label="운영 현황 요약">
        <div><span>전체 의견</span><strong>{info['total']}건</strong></div>
        <div><span>즉시·당일 확인</span><strong>{info['high_priority']}건</strong></div>
        <div><span>사람 검토 대기</span><strong>{info['pending']}건</strong></div>
        <div><span>분류 실패</span><strong>{info['failed']}건</strong></div>
      </section>
    """)
    st.caption("사람 검토가 끝나지 않은 항목은 운영 기준 적용 후의 잠정 분류로 집계합니다. 정확도 수치가 아닙니다.")

    category_col, priority_col = st.columns(2, gap="small")
    with category_col:
        with st.container(border=True, key="category_distribution"):
            st.markdown("## 유형별 의견")
            st.html(distribution_html(info["categories"],
                                      [*sorted(CATEGORIES), "UNCLASSIFIED"],
                                      {**CATEGORY_LABELS, "UNCLASSIFIED": "미분류"}))
    with priority_col:
        with st.container(border=True, key="priority_distribution"):
            st.markdown("## 우선순위별 의견")
            priority_labels = {**{code: display_priority(code) for code in SLA},
                               "UNCLASSIFIED": "미분류"}
            st.html(distribution_html(info["priorities"], [*SLA, "UNCLASSIFIED"], priority_labels))

    st.markdown("## 접수 패턴")
    st.caption("선택한 작업의 가상 데이터 한 묶음만 집계합니다. 날짜·채널 차이를 실제 운영 추세로 해석할 수는 없습니다.")
    trend_col, area_col = st.columns(2, gap="small")
    with trend_col:
        with st.container(border=True, key="date_distribution"):
            st.markdown("### 접수일별 건수")
            st.html(distribution_html(info["by_date"], sorted(info["by_date"]), {}))
    with area_col:
        with st.container(border=True, key="area_distribution"):
            st.markdown("### 제품 영역별 의견")
            st.dataframe([
                {"제품 영역": display(area, AREA_LABELS), "전체": count,
                 "P0·P1": info["area_urgent"][area]}
                for area, count in sorted(info["areas"].items(),
                                          key=lambda item: (-item[1], item[0]))
            ], hide_index=True, width="stretch")
        with st.container(border=True, key="channel_distribution"):
            st.markdown("### 접수 채널별 의견")
            st.html(distribution_html(info["channels"],
                                      sorted(info["channels"], key=lambda code: (-info["channels"][code], code)),
                                      CHANNEL_LABELS))

    with st.container(border=True, key="overview_urgent"):
        st.markdown("## 먼저 확인할 의견")
        st.caption("P0·P1 순서로 표시합니다. 최종 판단은 검토 작업에서 진행합니다.")
        urgent = info["urgent"]
        if urgent:
            st.dataframe([
                {"ID": row["voc_id"], "요약": row["summary"],
                 "우선순위": current_value(row, "priority"),
                 "유형": display(current_value(row, "category"), CATEGORY_LABELS),
                 "검토 상태": "검토 대기" if row["review_status"] == "PENDING" else "확인 완료"}
                for row in urgent
            ], hide_index=True, width="stretch")
        else:
            st.info("즉시·당일 확인할 의견이 없습니다.")

    with st.expander(f"전체 분류 결과 {info['total']}건 보기"):
        st.dataframe([
            {"ID": row["voc_id"], "요약": row["summary"],
             "유형": display(current_value(row, "category"), CATEGORY_LABELS),
             "우선순위": current_value(row, "priority") or "미분류",
             "담당": display(current_value(row, "owner"), OWNER_LABELS),
             "처리기한": row["final_sla"] or row["rule_sla"] or "확인 필요",
             "검토 상태": "검토 대기" if row["review_status"] == "PENDING" else "확인 완료"}
            for row in rows
        ], hide_index=True, width="stretch")


def classifier_label(model_name: str) -> str:
    if model_name == "heuristic-draft-v0":
        return "규칙 초안"
    return f"AI · {model_name}" if model_name else "확인 필요"


def import_batch(payload: bytes, engine: str) -> tuple[str, dict]:
    """Validate an uploaded CSV, run one isolated batch, and discard the raw copy."""
    if not payload or len(payload) > MAX_UPLOAD_BYTES:
        raise InputError("CSV 파일은 비어 있지 않아야 하며 1MB 이하여야 합니다")
    output_root = ROOT / "output"
    output_root.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("wb", suffix=".csv", prefix="voc-upload-",
                                     dir=output_root, delete=False) as handle:
        handle.write(payload)
        input_path = Path(handle.name)
    try:
        items = load_input(input_path)
        if len(items) > MAX_UPLOAD_ROWS:
            raise InputError(f"한 번에 {MAX_UPLOAD_ROWS}건까지 처리할 수 있습니다")
        if engine == "AI 분류":
            predictor = OpenAIClassifier(config_value("OPENAI_MODEL"))
        elif engine == "규칙 초안":
            predictor = None
        else:
            raise ValueError("지원하지 않는 처리 방식입니다")
        batch_id = datetime.now().astimezone().strftime("%Y%m%d-%H%M%S") + "-" + uuid4().hex[:6]
        output_dir = BATCHES / batch_id
        log = run(input_path, output_dir, **({"predictor": predictor} if predictor else {}))
        return batch_id, log
    finally:
        input_path.unlink(missing_ok=True)


def render_import() -> None:
    guide_col, action_col = st.columns([1, 1.4], gap="large")
    with guide_col:
        with st.container(border=True, key="import_guide"):
            st.markdown("## CSV 형식")
            st.write("VOC 한 건을 한 줄에 입력합니다. 처음이라면 예시 파일을 내려받아 작성하세요.")
            st.download_button(
                "예시 CSV 다운로드",
                ("\ufeffvoc_id,received_at,channel,platform,app_version,screen,user_text\n"
                 "SAMPLE-001,2026-10-20,beta_form,web,unknown,login,로그인 버튼을 누르면 화면이 멈춰요.\n").encode("utf-8"),
                file_name="mobv_voc_example.csv", mime="text/csv",
            )
            with st.expander("필수 열 7개 보기"):
                st.code("voc_id,received_at,channel,platform,app_version,screen,user_text",
                        language=None)
                st.caption("열 이름과 순서를 예시 파일과 같게 맞춰주세요. UTF-8 CSV, 최대 1MB · 100건")
    with action_col:
        with st.container(border=True, key="import_action"):
            st.markdown("## 새 작업 시작")
            st.warning(
                "가상 데모 CSV만 업로드하세요. 업로드·검토 결과는 실행 환경의 임시 파일에 저장되어 "
                "재시작이나 재배포 후 보존되지 않을 수 있습니다. 이메일·휴대전화 번호 외 개인정보는 "
                "자동으로 가리지 못합니다."
            )
            uploaded = st.file_uploader("VOC CSV 파일", type="csv", max_upload_size=1,
                                        help="UTF-8 CSV, 최대 1MB · 100건")
            engine = st.radio("분류 방식", ["AI 분류", "규칙 초안"], horizontal=True,
                              help="규칙 초안은 AI 모델을 호출하지 않는 개발용 처리 방식입니다.")
            st.caption("OpenAI API 사용 요금이 발생할 수 있습니다." if engine == "AI 분류"
                       else "AI를 호출하지 않고 규칙만 적용합니다.")
            if st.button("분류 시작", type="primary", use_container_width=True,
                         disabled=uploaded is None):
                try:
                    with st.spinner("CSV를 확인하고 분류하고 있습니다..."):
                        batch_id, log = import_batch(uploaded.getvalue(), engine)
                except (InputError, UnicodeError, OSError, ValueError) as exc:
                    st.error(f"분류를 시작할 수 없습니다: {exc}")
                else:
                    st.session_state["next_batch"] = batch_id
                    st.session_state["navigate_to"] = "검토 작업"
                    st.session_state["last_import"] = (
                        f"처리 {log['input_count']}건 · 성공 {log['success_count']}건 · "
                        f"실패 {log['failure_count']}건 · 확인할 의견 {log['review_count']}건"
                    )
                    st.rerun()


def render_history(batches: dict[str, tuple[Path, Path]]) -> None:
    history = []
    for batch_id, (source, reviewed_path) in batches.items():
        log_path = source.with_name("run_log.json")
        if not log_path.exists():
            continue
        try:
            log = json.loads(log_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(log, dict):
            continue
        try:
            reviewed_rows = load_session(source, reviewed_path)
            completed = sum(row["needs_review"] == "true" and
                            row["review_status"] != "PENDING" for row in reviewed_rows)
            review_progress = f"{completed}/{log.get('review_count', 0)}"
        except (OSError, ReviewError):
            review_progress = "확인 필요"
        history.append({
            "작업": batch_label(batch_id), "실행 시각": display_time(log.get("started_at", "")),
            "VOC 건수": log.get("input_count", 0), "확인할 의견": log.get("review_count", 0),
            "분류 실패": log.get("failure_count", 0),
            "분류 방식": classifier_label(log.get("model_name", "")),
            "확인 완료": review_progress,
        })
    if history:
        with st.container(key="history_table"):
            st.dataframe(history, hide_index=True, width="stretch")
        mobile_entries = "".join(f"""
            <article class="history-entry">
              <div class="history-entry-heading">
                <strong>{escape(str(item['작업']))}</strong>
                <span>확인 {escape(str(item['확인 완료']))}</span>
              </div>
              <p>{escape(str(item['실행 시각']))} · {escape(str(item['분류 방식']))}</p>
              <dl>
                <div><dt>VOC 건수</dt><dd>{escape(str(item['VOC 건수']))}건</dd></div>
                <div><dt>확인할 의견</dt><dd>{escape(str(item['확인할 의견']))}건</dd></div>
                <div><dt>분류 실패</dt><dd>{escape(str(item['분류 실패']))}건</dd></div>
              </dl>
            </article>
        """ for item in history)
        st.html(f'<section class="history-mobile" aria-label="실행 기록 목록">{mobile_entries}</section>')
        st.caption("확인 완료는 처리한 건수 / 확인이 필요한 건수입니다.")
    else:
        st.info("기록된 분류 실행이 없습니다.")

    batch_id = st.session_state.get("active_batch", "development")
    source, reviewed_path = batches[batch_id]
    if source.exists():
        with st.container(border=True, key="export_panel"):
            st.markdown("## 결과 내보내기")
            st.caption(batch_label(batch_id))
            export_col1, export_col2, export_col3 = st.columns(3)
            export_col1.download_button("자동 분류 결과 CSV", source.read_bytes(),
                                        file_name="classified_voc.csv", mime="text/csv",
                                        use_container_width=True)
            if reviewed_path.exists():
                export_col2.download_button("사람 검토 결과 CSV", reviewed_path.read_bytes(),
                                            file_name="reviewed_voc.csv", mime="text/csv",
                                            use_container_width=True)
            log_path = source.with_name("run_log.json")
            if log_path.exists():
                try:
                    report = render_weekly_report(
                        load_session(source, reviewed_path),
                        json.loads(log_path.read_text(encoding="utf-8")),
                    )
                except (OSError, ValueError, ReviewError) as exc:
                    st.warning(f"운영 요약을 만들 수 없습니다: {exc}")
                else:
                    export_col3.download_button("운영 요약 Markdown", report.encode("utf-8"),
                                                file_name="weekly_report.md", mime="text/markdown",
                                                use_container_width=True)


def render_header(page: str, batch_id: str) -> None:
    subtitles = {
        "검토 작업": "분류 결과를 확인하고 승인하거나 수정합니다.",
        "운영 현황": "유형과 우선순위를 한눈에 보고 먼저 확인할 의견을 찾습니다.",
        "CSV 가져오기": "CSV 파일을 올려 새 분류 작업을 시작합니다.",
        "실행 기록": "작업별 처리 결과와 검토 진행 상태를 확인합니다.",
    }
    context = "가상 데이터 데모" if page == "CSV 가져오기" else f"현재 작업 · {batch_label(batch_id)}"
    st.html(f"""
        <div class="mobv-header">
          <div class="mobv-brand">
            <h1>{escape(page)}</h1>
            <p>{escape(subtitles[page])}</p>
          </div>
          <span class="mobv-demo">{escape(context)}</span>
        </div>
    """)


def main() -> None:
    st.set_page_config(page_title="VOC 운영 센터 | Mobv", page_icon=":material/inbox:", layout="wide",
                       initial_sidebar_state="auto")
    st.html(ROOT / "dashboard.css")
    batches = available_batches()
    with st.sidebar:
        st.html('<span class="mobv-logo-lockup">'
                '<img class="mobv-wordmark mobv-wordmark-light" src="app/static/mobv-wordmark.png" '
                'width="150" height="47" alt="Mobv">'
                '<img class="mobv-wordmark mobv-wordmark-color" src="app/static/mobv-wordmark.png" '
                'width="150" height="47" alt="" aria-hidden="true">'
                '</span>')
        st.caption("VOC 운영 센터 · 가상 데이터 데모")
        if "navigate_to" in st.session_state:
            st.session_state["page"] = st.session_state.pop("navigate_to")
        page = st.radio("메뉴", ["검토 작업", "운영 현황", "CSV 가져오기", "실행 기록"], key="page",
                        label_visibility="collapsed")
        st.divider()
        if "next_batch" in st.session_state:
            st.session_state["active_batch"] = st.session_state.pop("next_batch")
        if st.session_state.get("active_batch") not in batches:
            st.session_state["active_batch"] = "development"
        batch_id = st.selectbox("작업 선택", list(batches), format_func=batch_label,
                                key="active_batch")
        st.caption("작업을 선택하면 해당 의견 목록이 열립니다.")
    render_header(page, batch_id)
    if "last_import" in st.session_state:
        st.success(st.session_state.pop("last_import"))
    if page == "운영 현황":
        render_overview(*batches[batch_id])
    elif page == "CSV 가져오기":
        render_import()
    elif page == "실행 기록":
        render_history(batches)
    else:
        render_review(*batches[batch_id])


if __name__ == "__main__":
    main()
