# Mobv VOC 출력 스키마

| 항목 | 내용 |
| --- | --- |
| 버전 | v1.0 |
| 기준일 | 2026-10-16 |
| 목적 | AI 최초 판단, 규칙 검증, 사람의 최종 판단을 분리해 기록한다. |

## 1. 입력 스키마

### 필수 필드

| 필드 | 형식 | 설명 | 검증 |
| --- | --- | --- | --- |
| `voc_id` | 문자열 | VOC 고유 ID | 비어 있지 않고 파일 내 중복 없음 |
| `received_at` | `YYYY-MM-DD` | 접수일 | 유효한 날짜 |
| `channel` | 문자열 | 접수 채널 | 허용값 검증 |
| `platform` | 문자열 | 발생 플랫폼 | 허용값 검증 |
| `app_version` | 문자열 | 앱 버전 | 비어 있으면 `unknown` 허용 |
| `screen` | 문자열 | 발생 화면 | 허용값 또는 `unknown` |
| `user_text` | 문자열 | VOC 원문 | 공백 제외 1자 이상 |

### 입력 허용값

```text
channel: beta_form, in_app, email, store_review, usability_test
platform: android, ios, web, unknown
screen: login, home, appointment, date_coordination, map, recommendation, voting, history, common, unknown
```

### 입력 처리 원칙

- 원본 CSV는 수정하지 않는다.
- 처리용 복사본에서 앞뒤 공백과 비정상 줄바꿈만 정리한다.
- 개인정보 패턴은 AI 호출 전에 마스킹한다.
- 원문 보존이 필요한 경우 로컬 원본에만 남기고 공개 산출물에는 포함하지 않는다.
- 가상 개인정보는 `example.com` 등 명백한 테스트 값만 사용한다.

---

## 2. AI 구조화 출력

AI는 각 VOC마다 다음 JSON 구조만 반환한다.

```json
{
  "voc_id": "VOC-001",
  "summary": "로그인 버튼을 누르면 앱이 종료됨",
  "product_area": "AUTH",
  "category": "BUG",
  "secondary_category": null,
  "priority": "P1",
  "owner": "DEVELOPMENT",
  "secondary_owner": null,
  "sla": "당일",
  "confidence": "HIGH",
  "reason": "로그인이 불가능해 핵심 진입 흐름이 차단됨"
}
```

### AI 허용값

```text
category: BUG, USABILITY, REQUEST, ACCOUNT, POLICY, INFORMATION, ETC
product_area: AUTH, APPOINTMENT, DATE_COORDINATION, MAP_LOCATION, RECOMMENDATION, VOTING, HISTORY, COMMON
priority: P0, P1, P2, P3
owner: DEVELOPMENT, DESIGN_UX, PRODUCT, OPERATIONS, POLICY_SECURITY, NEEDS_TRIAGE
confidence: HIGH, MEDIUM, LOW
sla: 즉시 확인, 당일, 3영업일 이내, 5영업일 이내
```

숫자형 확신도는 사용하지 않는다. `confidence`는 참고값이며 자동 확정 근거로 사용하지 않는다.

---

## 3. 최종 결과 스키마

### 식별·원문 필드

| 필드 | 설명 |
| --- | --- |
| `voc_id` | VOC 고유 ID |
| `received_at` | 접수일 |
| `channel` | 접수 채널 |
| `platform` | 발생 플랫폼 |
| `app_version` | 앱 버전 |
| `screen` | 발생 화면 |
| `user_text_redacted` | 개인정보가 마스킹된 VOC 원문 |

### AI 최초 판단 필드

| 필드 | 설명 |
| --- | --- |
| `summary` | 한 줄 요약 |
| `product_area` | 제품 영역 |
| `ai_category` | AI 대표 유형 |
| `ai_secondary_category` | AI 보조 유형 |
| `ai_priority` | AI 우선순위 |
| `ai_owner` | AI 담당 영역 |
| `ai_secondary_owner` | AI 보조 담당 영역 |
| `ai_sla` | AI 권장 처리기한 |
| `ai_confidence` | AI 참고 확신도 |
| `ai_reason` | AI 판단 이유 |

### 규칙 검증 필드

| 필드 | 설명 |
| --- | --- |
| `rule_category` | 규칙 적용 후 유형 |
| `rule_priority` | 규칙 적용 후 우선순위 |
| `rule_owner` | 규칙 적용 후 담당 영역 |
| `rule_sla` | 규칙 적용 후 처리기한 |
| `review_flags` | `|`로 연결한 검토 플래그 |
| `needs_review` | 사람 검토 필요 여부 |
| `rule_reason` | 규칙 보정 또는 검토 표시 이유 |

규칙이 값을 바꾸지 않았다면 `rule_*`에는 AI 값을 그대로 복사한다. 최종 판단의 기준값이 무엇인지 모호하지 않게 하기 위함이다.

### 사람 검토 필드

| 필드 | 설명 |
| --- | --- |
| `review_status` | `PENDING`, `APPROVED`, `MODIFIED` |
| `final_category` | 사람 검토 후 최종 유형 |
| `final_priority` | 사람 검토 후 최종 우선순위 |
| `final_owner` | 사람 검토 후 최종 담당 영역 |
| `final_sla` | 사람 검토 후 최종 처리기한 |
| `correction_reason` | 수정 이유. `MODIFIED`일 때 필수 |
| `reviewed_at` | 검토 완료 시각, ISO 8601 |

### 실행 추적 필드

| 필드 | 설명 |
| --- | --- |
| `run_id` | 실행 단위 고유 ID |
| `prompt_version` | 프롬프트 버전 |
| `policy_version` | 분류 정책 버전 |
| `model_name` | 사용 모델 이름 |
| `processed_at` | 처리 시각, ISO 8601 |
| `processing_status` | `SUCCESS`, `FAILED` |
| `error_message` | 실패 사유 |

---

## 4. 최종 CSV 열 순서

```text
voc_id
received_at
channel
platform
app_version
screen
user_text_redacted
summary
product_area
ai_category
ai_secondary_category
ai_priority
ai_owner
ai_secondary_owner
ai_sla
ai_confidence
ai_reason
rule_category
rule_priority
rule_owner
rule_sla
review_flags
needs_review
rule_reason
review_status
final_category
final_priority
final_owner
final_sla
correction_reason
reviewed_at
run_id
prompt_version
policy_version
model_name
processed_at
processing_status
error_message
```

---

## 5. 검토 상태 규칙

### 초기값

| 조건 | `review_status` | 최종값 |
| --- | --- | --- |
| `needs_review=true` | `PENDING` | 비어 있음 |
| `needs_review=false` | `APPROVED` | `rule_*` 값을 복사 |

### 사람 검토 후

| 행동 | `review_status` | 처리 |
| --- | --- | --- |
| 규칙 결과 그대로 승인 | `APPROVED` | `rule_*`를 `final_*`에 복사 |
| 하나 이상 수정 | `MODIFIED` | 수정값과 `correction_reason` 저장 |

`MODIFIED`인데 `correction_reason`이 없으면 저장할 수 없다.

---

## 6. 정답 데이터 스키마

정답 파일은 AI 출력과 분리한다.

```text
voc_id
gold_category
gold_product_area
gold_priority
gold_owner
gold_sla
gold_review_flags
gold_needs_review
gold_reason
```

평가 실행 중 정답 파일의 필드를 프롬프트나 분류 입력에 포함하지 않는다.

---

## 7. 실행 로그 스키마

`run_log.json`은 다음 내용을 기록한다.

```json
{
  "run_id": "RUN-20261016-001",
  "started_at": "2026-10-16T10:00:00+09:00",
  "finished_at": "2026-10-16T10:02:30+09:00",
  "input_file": "development_voc.csv",
  "input_count": 30,
  "success_count": 29,
  "failure_count": 1,
  "review_count": 8,
  "rule_override_count": 3,
  "prompt_version": "v1.0",
  "policy_version": "v1.0",
  "model_name": "TBD",
  "elapsed_seconds": 150,
  "errors": [
    {"voc_id": "VOC-019", "error": "invalid structured output"}
  ]
}
```

---

## 8. 파일 구성

```text
voc-ops/
  data/
    development_voc.csv
    development_gold.csv
    evaluation_voc.csv
    evaluation_gold.csv
  output/
    classified_voc.csv
    review_queue.csv
    reviewed_voc.csv
    weekly_report.md
    run_log.json
  docs/
    classification-policy.md
    output-schema.md
```

`evaluation_gold.csv`는 최종 평가 단계에서만 읽는다.
