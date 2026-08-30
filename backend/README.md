# Mobv Backend

여러 명이 각자 그린 "이동 가능 범위"의 교집합을 계산하고, 그 안에서 만날 장소를 추천하는 Flask API 서버입니다.

## 빠른 시작

```bash
pip install flask flask-cors shapely pyproj python-dotenv requests pytest
```

`.env` 파일:
```
KAKAO_REST_KEY=카카오_로컬_API_REST_키
OPENWEATHER_API_KEY=오픈웨더맵_키
FLASK_DEBUG=false   # 배포 환경 필수. 로컬 디버깅 때만 true
```

```bash
python app.py   # http://localhost:5000
```

## API

### `POST /recommend`

**요청**
```json
{
  "users": [
    {"lat": 37.5665, "lng": 126.9780, "radius": 1500},
    {"lat": 37.5675, "lng": 126.9790, "radius": 1500}
  ],
  "category": "cafe"
}
```
| 필드 | 설명 |
|---|---|
| `users` | 2~5명. 각 `lat`(-90~90) / `lng`(-180~180) / `radius`(0 초과 ~20000m) |
| `category` | `cafe`/`restaurant`/`bar`/`study` (프론트 실제 선택지) 또는 17개 한글 카테고리 (아래 참고) |

**응답 — 세 가지 케이스**

| 상황 | `hasIntersection` | `places` | 추가 필드 |
|---|---|---|---|
| 전원 교집합 있음 | `true` | 채워짐 | `area_name`, `search_radius`, `weather` |
| 일부만 겹침 | `false` | `[]` | `partialMatch` |
| 아무 조합도 안 겹침 | `false` | `[]` | 없음 (키 자체가 없음) |

```json
// 전원 교집합 있음
{
  "hasIntersection": true, "area_name": "시청역",
  "center_lat": 37.567, "center_lng": 126.9785, "search_radius": 1452,
  "weather": {"condition": "clouds", "description": "흐림", "temp": 24.8},
  "places": [{"name": "...", "category": "...", "distance": 765, "url": "...", "...": "..."}]
}

// 일부만 겹침
{
  "hasIntersection": false,
  "message": "거의 다 만날 수 있는 지점이에요. 조금만 반경을 넓히면 될 것 같아요.",
  "places": [],
  "partialMatch": {"center_lat": 37.567, "center_lng": 126.9785, "matched_count": 4, "total_count": 5, "search_radius": 1452}
}

// 아무 조합도 안 겹침
{ "hasIntersection": false, "message": "겹치는 지역이 없어요. 반경을 조금만 넓히면 새로운 추천 결과를 볼 수 있어요.", "places": [] }
```

### `GET /weather/forecast?lat=&lng=&date=`
약속 날짜의 예보 날씨. 5일 초과 시 `condition: "unknown"`.

## 폴더 구조

| 파일 | 역할 |
|---|---|
| `app.py` | 라우트, 입력 검증, 에러 핸들링 |
| `recommend/intersection.py` | 원 교집합 계산, 부분 매칭 |
| `recommend/place.py` | 카카오 로컬 API 검색 (타임아웃/파싱 방어, radius 20000 clamp) |
| `recommend/query_builder.py` | 카테고리 → 검색어/필터, 프랜차이즈 블랙리스트 |
| `recommend/midpoint.py` | 교집합 중심에서 가장 가까운 지하철역 |
| `recommend/weather.py` | 날씨 (참고용, 검색 로직엔 관여 안 함) |

## 카테고리

**프론트 실제 선택지 4개**: `cafe`(카페) / `restaurant`(맛집) / `bar`(술집) / `study`(카공카페)

**백엔드 지원 나머지 13개** (한글 값 그대로 보내면 동작): 한식·마라탕·돈까스·라멘·파스타·피자·초밥·고기·국밥·분식·이자카야·바·디저트

`study`는 "여럿이 카페에서 노트북 작업"용이며, 개인 열람실형 "스터디카페"(공간대여업)와는 다른 개념입니다. 카카오 API가 와이파이/콘센트 정보를 안 줘서 완벽한 필터링은 불가능하고, 검색어(`카공카페`+`조용한 카페`)로 얻을 수 있는 최선까지만 합니다. 최종 판단은 사용자가 카카오맵 링크로 확인.

## 테스트

```bash
python -m pytest test_recommend.py -v   # 48개, 전부 mock — 로직 검증
python smoke_test.py                     # 실제 API 호출 — 배포 전 눈으로 확인
```

## 알려진 제약사항

- 카카오 로컬 API에 평점/리뷰/편의시설 정보 없음 → `study` 카테고리 품질 제한적
- `find_best_midpoint`는 카카오 검색 상위 5개(`sort=accuracy`) 안에서만 역을 찾음

## 향후 계획 (우선순위 순, 전부 급하지 않음)

**1. (최우선) 교집합 실패 메시지 톤 — "인원수" 대신 "실제 거리" 기준으로**

지금은 `missing = total - matched`가 1 이하면 "거의 다 됐다" 톤을 씁니다. 하지만 신촌 4명 + 강남 1명처럼 `missing=1`이어도 실제 격차가 8km+ 일 수 있어(재현 확인함), 인원수만으로는 부정확합니다. 완전 매칭 실패(서울-부산) 폴백 메시지도 같은 문제입니다.
→ `find_best_partial_intersection`이 "제외된 사용자가 매칭 영역까지 얼마나 떨어져 있는지" 집계값(개인 지목 없이)을 같이 반환하고, 그 값으로 톤을 결정하도록 변경.

**2. `_validate_users`의 bool 허점**

```python
if not isinstance(u[key], (int, float)):   # bool은 int의 서브클래스라 True/False가 통과함
```
```python
if isinstance(u[key], bool) or not isinstance(u[key], (int, float)):
```

**3. 지하철역 검색 — `sort=accuracy` 대신 `sort=distance` 검토**

일반 장소 검색은 관련도 기준이 맞지만, 역 찾기는 순수 거리가 중요한 용도라 다를 수 있음. `size=5` 제한과 겹쳐 진짜 최근접 역을 놓칠 가능성. "역 라벨이 이상하다"는 피드백이 나오면 여기부터 의심.

**그 외 보류 중**: 16개 카테고리 UI 확장(백엔드 준비 완료, 프론트 스코프 아님) / [cagongi.com](https://cagongi.com)(전국 카공카페 DB) 연동 검토(API·이용약관 확인 필요)

## 핵심 원칙

1. 정직한 계산만 한다 — 잴 수 없는 걸 잰 척하지 않는다
2. 서버가 사용자의 선택을 임의로 바꾸지 않는다
3. 누구도 지목하지 않는다
4. 공정성 도구다 — 한 사람이 부담을 몰아서 지지 않게 한다
5. 교집합 = 모두가 허용한 구역 — 아닌 걸 그런 척 포장하지 않는다

새 기능 추가 전에 이 원칙과 충돌하는지 먼저 확인하세요.