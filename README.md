# Mobv VOC 운영 도구

이 프로젝트는 **가상 VOC**로 운영 흐름을 시험한다. 기본 `draft` 실행은 `heuristic-draft-v0`이라는 결정적 규칙 초안이다. 이 모드의 `ai_*` 열은 최종 출력 형식을 미리 맞추기 위해 채우며 **AI 모델 호출 결과가 아니다**. `openai` 모드는 별도의 API 키와 모델 ID가 있을 때 실제 모델을 호출한다. 실제 고객 문의·운영 성과로 해석하지 않는다.

## 개발 세트 처리

프로젝트 폴더에서 다음을 실행한다.

```powershell
python scripts/classify_voc.py
```

기본 입력은 `data/development_voc.csv` 30건이다. 다른 CSV를 처리할 때는 `--input`과 `--output-dir`을 지정한다. 입력 CSV는 `docs/output-schema.md`의 7개 열과 순서를 따라야 한다. 빈 앱 버전은 `unknown`으로 정규화하고, 허용값·날짜·빈 원문·중복 ID를 검증한다. 검증에 실패하면 출력 파일을 만들지 않는다. 원본 입력 파일은 수정하지 않는다.

이메일과 휴대전화 형식은 분류 전에 `[EMAIL]`, `[PHONE]`으로 마스킹한다. 결과는 `output/classified_voc.csv`, `output/review_queue.csv`, `output/run_log.json`에 저장된다. 같은 출력 폴더로 다시 실행하면 이 세 파일을 갱신한다. 주간 리포트는 이후 작업이다.

## 실제 AI 모델 실행

프로젝트 폴더의 [.env.example](.env.example)을 `.env`로 복사한 뒤 `OPENAI_API_KEY`와 `OPENAI_MODEL` 값을 채운다. `.env`와 `.streamlit/secrets.toml`은 Git에서 제외된다. 키를 CSV나 코드에 적거나 채팅에 보내지 않는다. 이미 셸 환경 변수를 사용 중이라면 환경 변수 값이 `.env`보다 우선한다. Streamlit Community Cloud에서는 앱 설정의 Secrets에 두 값을 등록하며, 앱은 `st.secrets`에서 읽는다.

```powershell
Copy-Item .env.example .env
# .env에 실제 키와 모델 ID를 입력한 뒤
python scripts/classify_voc.py --engine openai
```

명령에서 `--model <모델-ID>`를 지정하면 `.env`의 `OPENAI_MODEL`보다 우선한다. 이 모드의 기본 결과 폴더는 `output/openai/`이므로 규칙 초안 결과를 덮어쓰지 않는다. 입력은 한 건씩 마스킹되어 [OpenAI Responses API](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses)에 전송된다. 요청에는 엄격한 JSON 스키마와 `store=false`를 사용한다. 응답은 다시 허용값·VOC ID·우선순위별 SLA를 검사한다. 일시적 API 오류나 잘못된 응답은 기본 두 번까지 시도하고, 끝내 실패한 건은 `processing_status=FAILED`, `needs_review=true`로 검토 큐에 남긴다. API 사용량에 따른 비용이 발생할 수 있다.

API 키나 모델 ID가 없으면 이 모드는 실행 전에 오류를 내며 규칙 초안으로 조용히 대체하지 않는다. 2026-10-19에 `gpt-6-luna`로 개발 세트 30건을 실제 처리했다. 성공 30건, 실패 0건, 검토 17건이었다. 2026-10-20 기본 규칙 초안의 독립 평가는 완료했으며, 실제 OpenAI 모델 평가는 별도 API 비용 확인이 필요하다.

## 독립 평가

2026-10-20에 `data/evaluation_voc.csv` 20건으로 기본 `heuristic-draft-v0`를 평가했다. 6개 주요 항목 완전 일치는 5/20 (25%), 검토 필요 여부 일치는 13/20 (65%)였다. 자세한 방법·항목별 결과·한계는 [독립 평가 결과](docs/evaluation-results-2026-10-20.md)를 참고한다. 이 수치는 실제 OpenAI 모델이나 실제 고객 VOC의 성능을 나타내지 않는다.

개발 세트와 정답의 차이만 확인하려면 다음을 실행한다. 이 스크립트는 평가 정답 파일을 읽지 않는다.

```powershell
python scripts/check_development.py
python -m unittest discover -s tests -v
```

## 실제 사람의 수작업 기준선

수작업 처리시간은 도구를 만드는 사람이 추정하거나 CLI 실행시간으로 대신하지 않는다. [수작업 측정 안내](docs/manual-baseline-guide.md)의 코드 뜻을 먼저 익힌 뒤, 사람이 자동 분류 결과나 정답을 열지 않은 상태에서 다음을 실행해 직접 판단한다. 처음 측정 시도에서 기존 입력의 첫 3건을 보았으므로, 기본 입력은 답이 없는 새 가상 VOC [manual_baseline_v2_voc.csv](data/manual_baseline_v2_voc.csv) 30건으로 바꿨다. 이전 [manual_baseline_voc.csv](data/manual_baseline_voc.csv)는 새 기준선으로 사용하지 않는다.

```powershell
python scripts/manual_baseline.py
```

시작 프롬프트에서 Enter를 누른 때부터 마지막 건의 판단을 마친 때까지 측정한다. 각 건의 유형·제품 영역·우선순위·담당과 어려웠던 판단을 기록한다. 완료하면 `output/manual_baseline.csv`와 `output/manual_baseline.json`에 시작·종료 시각, 총 소요 시간, 건별 소요 시간과 메모가 저장된다. 중단된 세션은 기준선으로 저장하지 않는다. **수작업 시간 측정은 이번 MVP에서 생략하기로 했다.** 따라서 사람 대비 시간 절감률은 보고하지 않는다. 도구는 나중에 측정할 수 있도록 남겨 둔다.

## 사람 검토 기록

실제 AI 개발 세트의 검토 대상 17건을 확인한다. 수작업 시간 측정을 하지 않아도 검토는 진행할 수 있다.

```powershell
python scripts/review_voc.py
```

각 건에서 `a`는 규칙 결과 그대로 승인, `m`은 최종 유형·우선순위·담당을 수정, `s`는 건너뛰기, `q`는 종료다. 수정할 때는 이유가 필수다. 한 건을 확정할 때마다 `output/openai/reviewed_voc.csv`에 **전체 30건의 현재 상태**를 저장하므로 중단 후 같은 명령으로 재개할 수 있다. 원래 `classified_voc.csv`와 `review_queue.csv`는 바꾸지 않는다. 검토 상태가 `PENDING`인 건은 아직 사람의 최종 판단이 아니다. AI 호출이 실패한 건은 빈 규칙값을 그대로 승인할 수 없고 사람이 값을 입력해야 한다.

분류 실행을 다시 해 `run_id`가 바뀌었다면 이전 검토 파일을 자동으로 이어 쓰지 않는다. 새 실행을 검토할 때는 `--output`으로 별도 저장 경로를 지정한다.

## 로컬 검토 화면

프로젝트 폴더에서 가상환경을 만들고 Streamlit을 설치한 뒤 실행한다.

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m streamlit run dashboard.py
```

화면의 **CSV 가져오기**에서 입력 스키마에 맞는 UTF-8 CSV를 올려 새 분류 작업을 시작할 수 있다. 한 번에 100건, 1MB까지 받는다. **AI 분류**는 환경 변수, `.env` 또는 Streamlit Secrets의 키와 모델을 사용해 OpenAI API를 호출하며, **규칙 초안**은 모델을 호출하지 않는다. 분류를 시작하기 전 입력 전체를 검증하고, 업로드 원본의 임시 복사본은 처리 후 삭제한다. 결과는 작업별 `output/batches/<작업 ID>/`에 분리해 저장한다.

**검토 작업**에서 작업 데이터를 선택하면 검토 대기 건수와 AI·규칙 판단, 마스킹된 VOC가 표시된다. 사람이 규칙 결과를 승인하거나 유형·우선순위·담당을 수정하고 이유를 입력하면 선택한 작업의 `reviewed_voc.csv`에 저장된다. 기존 분류 결과 파일은 보존된다. **실행 기록**에서는 작업별 처리 건수와 실패 건수를 볼 수 있다.

현재는 로컬 시뮬레이션으로, 개인정보 마스킹 범위가 이메일과 휴대전화 형식에 한정된다. 실제 고객 데이터를 입력하기 전에 인증·접근 제어와 개인정보 처리 범위를 보강해야 한다. 대시보드는 사람의 실제 승인·수정을 대신하지 않는다.

Day 3에서 확인한 정책 경계는 [작업 메모](docs/day3-notes.md), Day 4 구현 상태는 [Day 4 작업 메모](docs/day4-notes.md)에 정리했다.

## Streamlit Community Cloud 데모

데모 주소는 [mobv-voc-op.streamlit.app](https://mobv-voc-op.streamlit.app/)이다. 비공개 저장소 `RedHareTeam/mobv`의 `voc-ops` 브랜치에서 `dashboard.py`를 진입 파일로 배포했다. 2026-10-20에 주소의 HTTP 응답과 사용자 브라우저의 대시보드 제목을 확인했다. 접근 범위와 배포 URL에서의 실제 화면 동작은 추가 확인이 필요하다.

기존 30건의 가상 VOC와 17건의 검토 대기 결과를 화면에서 살펴보는 데 API 키는 필요하지 않다. 새 CSV의 **AI 분류**를 활성화할 때만 앱 설정의 Secrets에 `OPENAI_API_KEY`와 `OPENAI_MODEL`을 추가한다. 데모 화면에는 가상 데이터만 사용한다. 업로드·검토 결과는 실행 환경의 임시 파일에 저장되므로 재시작·재배포 후 보존을 보장하지 않으며, 이 서비스는 실제 운영용이 아니다.
