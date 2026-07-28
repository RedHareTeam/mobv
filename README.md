# Mobv Backend

> 모두가 괜찮은 곳에서 만나요 — 선호 범위 교집합 기반 약속 장소 추천 API

---

### category

- 교집합 확인 후 사용자가 카테고리를 선택하는 화면 추가
- 선택한 `category` 값을 `/recommend` 요청에 포함
- 고정 버튼 + 직접 입력창 조합 권장
- 직접 입력: 자유 텍스트
- 영어 값(`cafe`, `restaurant` 등)도 백엔드에서 자동으로 한글 카테고리로 변환됨

```

맛집, 술집, 카페, 디저트, 고기, 라멘, 초밥, 피자, 파스타, 마라탕, 국밥

──────────────────────────────
직접 검색  [ 우동________________ ]
```

> 백엔드는 고정 카테고리 외 자유 검색도 지원
> `category`에 "우동", "냉면", "브런치" 등 넣으면 카카오 키워드 검색으로 그대로 넘어감.

---

## 1주차 변경 사항 (Chemeet → Mobv 리뉴얼)

### 제거한 것들

| 항목 | 이유 |
|---|---|
| `kakao_parser.py` | 카카오톡 대화 파싱 — 업로드 기능 제거로 불필요 |
| `openai_analyzer.py` | GPT-4o-mini 취향 분석 — 업로드 기능 제거로 불필요 |
| `rule_based.py` | 친밀도 점수 / 반경 확장 로직 |
| `transit.py` | ODsay 대중교통 이동시간 계산 |
| `/analyze` 엔드포인트 | 카카오톡 분석 API 전체 |
| `intimacy_score`, `radius_expansion` 파라미터 | 카카오톡 분석 없이 의미 없음 |
| 교집합 없을 때 중간지점 fallback | "겹치는 곳 없음" 안내로 대체 |
| 날씨 기반 반경 자동 조정 | 사용자가 직접 그린 원을 서버가 임의로 변경하는 구조 제거 |

### 변경한 것들

| 항목 | 변경 내용 |
|---|---|
| `midpoint.py` | ODsay 제거 → 교집합 centroid 기준 가장 가까운 지하철역 선택으로 단순화 |
| `intersection.py` | 교집합 없을 때 fallback 제거 → `has_intersection: False` 반환 |
| `query_builder.py` | mood/purpose/preferred_food 기반 복잡한 쿼리 → **카테고리 단일 선택** 방식으로 단순화 |
| `/recommend` 요청 형식 | `user1/user2` → `users` 리스트, `place_type/mood` → `category` |
| `/recommend` 응답 형식 | `has_intersection` → `hasIntersection` (camelCase), `users_transit/total_time` 제거 |

### 추가한 것들

| 항목 | 내용 |
|---|---|
| 카테고리 기반 장소 검색 | 사용자가 직접 카테고리 선택 (카페/한식/라멘/피자 등 15개) |
| 프랜차이즈 블랙리스트 | 카페(저가 프랜차이즈), 피자(대형 체인), 한식(빠른 식사용) 필터링 |
| 멀티쿼리 검색 | 파스타/피자는 2개 쿼리 병렬 검색으로 결과 수 보완 |
| shape 기반 교집합 필터 | 교집합 shape을 한 번만 계산해서 장소 필터링에 재사용 |

---

## 2주차 변경 사항

### 제거한 것들

| 항목 | 이유 |
|---|---|
| `user1/user2` 구버전 호환 코드 | 프론트가 `users` 리스트 형식으로 완전히 전환됨에 따라 정리 |
| `weather.py`의 `apply_weather_filter` | 1주차에 이미 미사용 처리된 날씨 기반 반경 조정 로직의 잔여 함수 |

### 추가한 것들

| 항목 | 내용 |
|---|---|
| `CATEGORY_MAP_EN` | 영어 카테고리 값(`cafe`, `restaurant`, `bar`, `dessert`, `meat`, `ramen`, `sushi`, `pizza`, `pasta`, `malatang`, `gukbap`, `korean`, `chinese`, `japanese`, `cutlet`, `izakaya`)을 한글로 자동 변환 |
| Firestore Security Rules | `memberProfiles` 맵 구조 기준으로 설계 및 게시 완료. 약속 문서는 멤버만 읽기/수정 가능, 생성자만 삭제 가능. `circles`/`availabilities` 서브컬렉션은 본인 uid 문서만 쓰기 가능 |
| 다자간(3~5인) 교집합 검증 테스트 | 정상 케이스(신촌 생활권 좌표)와 실패 케이스(원거리 좌표) 모두 검증하는 테스트 시나리오 추가 |


---

## API 명세

### POST /recommend

**요청**

```json
{
  "users": [
    {"lat": 37.5573, "lng": 126.9245, "radius": 3000},
    {"lat": 37.5443, "lng": 126.9526, "radius": 3000}
  ],
  "category": "라멘"
}
```

| 필드 | 타입 | 설명 |
|---|---|---|
| `users` | Array | 2~5명의 위치/반경 정보 |
| `users[].lat` | float | 위도 |
| `users[].lng` | float | 경도 |
| `users[].radius` | int | 반경 (미터) |
| `category` | string | 장소 카테고리 (아래 목록 참고). 영어 값도 자동 변환됨 |

**지원 카테고리 (한글)**

```
카페, 디저트
한식, 중식, 돈까스, 라멘, 파스타, 피자, 초밥, 고기, 국밥, 분식
술집, 이자카야, 바
```

**지원 카테고리 (영어 → 자동 변환)**

```
cafe, restaurant, bar, dessert, meat, ramen, sushi,
pizza, pasta, malatang, gukbap, korean, chinese, japanese,
cutlet, izakaya
```

**응답 — 교집합 있을 때**

```json
{
  "hasIntersection": true,
  "area_name": "서강대역 경의중앙선",
  "center_lat": 37.550801,
  "center_lng": 126.938551,
  "search_radius": 3994,
  "weather": {
    "condition": "clouds",
    "temp": 25.1,
    "description": "구름조금"
  },
  "places": [
    {
      "name": "멘야요시",
      "address": "서울 마포구 ...",
      "category": "음식점 > 일식 > 라멘",
      "lat": 37.549,
      "lng": 126.937,
      "url": "https://place.map.kakao.com/...",
      "distance": 195,
      "kakaoId": "12345678"
    }
  ]
}
```

**응답 — 교집합 없을 때**

```json
{
  "hasIntersection": false,
  "message": "겹치는 지역이 없어요. 반경을 조금만 넓히면 새로운 추천 결과를 볼 수 있어요.",
  "places": []
}
```

**에러 응답**

| 상태코드 | 설명 |
|---|---|
| 400 | users가 없거나 2명 미만, 또는 5명 초과 |
| 422 | 추천 장소가 2개 미만 (원을 더 넓게 그려야 함) |

---

### GET /weather/forecast

약속 날짜의 예보 날씨 반환 (OpenWeatherMap 5일 예보, 무료 플랜 기준)

**요청**

```
GET /weather/forecast?date=2026-07-01&lat=37.5665&lng=126.9780
```

**응답**

```json
{
  "condition": "clear",
  "temp": 28.5,
  "description": "맑음"
}
```

---

## Firestore Security Rules

`appointments` 문서가 `members` 배열이 아니라 `memberProfiles` 맵(key: uid) 구조를 사용한다는 점을 기준으로 설계했다.

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    match /appointments/{appointmentId} {
      allow read: if request.auth != null
        && request.auth.uid in resource.data.memberProfiles;
      allow update: if request.auth != null
        && request.auth.uid in resource.data.memberProfiles;
      allow create: if request.auth != null;
      allow delete: if request.auth != null
        && request.auth.uid == resource.data.createdBy;

      match /circles/{uid} {
        allow read: if request.auth != null;
        allow write: if request.auth != null
          && request.auth.uid == uid;
      }

      match /availabilities/{uid} {
        allow read: if request.auth != null;
        allow write: if request.auth != null
          && request.auth.uid == uid;
      }

      match /votes/{voteId} {
        allow read: if request.auth != null;
        allow write: if request.auth != null;
      }

      match /messages/{messageId} {
        allow read: if request.auth != null;
        allow write: if request.auth != null;
      }
    }

    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null
        && request.auth.uid == userId;
    }
  }
}
```

`availabilities`는 날짜 조율 기능이 아직 구현되지 않아 실제 데이터는 없지만, 추후 구현을 대비해 미리 규칙에 포함했다.

---

## 앞으로 고려할 것들

### 카테고리 관련

- [x] **교집합 확인 후 카테고리 선택** (채택)
  - 위치를 먼저 결정한 뒤 장소 종류를 선택하는 흐름이 자연스럽고 변경도 쉬움
  - 방 생성 시 미리 선택하면 나중에 바꾸기 어려운 문제 방지
- [x] **영어 카테고리 값 자동 변환** (2주차 임시 대응)
  - 프론트 카테고리 선택 UI가 확정되면 매핑 유지 여부 재검토 필요
- [ ] 복수 선택 (최대 2~3개)
  - MVP에서는 제외. 집계/동점처리/우선순위 추가 구현 필요
  - 사용자 피드백 바탕으로 추후 검토
- [x] **자유 검색 지원** (MVP부터 지원)
  - "우동", "냉면", "브런치" 등 고정 카테고리 외 키워드 직접 입력 가능
  - 백엔드 이미 지원: `category`에 없는 값은 카카오 키워드 검색으로 그대로 넘어감

## 카카오 로컬 API vs Google Places API 비교

1주차에 두 API를 동일 좌표/반경으로 직접 테스트한 결과.

### 테스트 조건

- 테스트 지역: 홍대, 강남, 성수 (주요 상권) / 망원, 연남, 을지로 (골목 상권)
- 반경: 1500m
- 카테고리: 카페, 맛집, 술집

### 결과 요약

| 항목 | 카카오 로컬 API | Google Places API |
|---|---|---|
| 결과 수 | 동일 (최대 15개) | 동일 (최대 20개) |
| 장소명 품질 | ✅ 한국어 깔끔 | ❌ 영어/중국어/일본어 섞임 |
| 골목 상권 커버리지 | ✅ 해당 동네 로컬 가게 | ❌ 인근 핫플 끌어옴 |
| 평점/사진/영업시간 | ❌ 없음 | ✅ 있음 |
| 지역 정확도 | ✅ 높음 | ❌ 낮음 (망원 검색 → 홍대 맛집 반환) |
| 자연어 검색 | ❌ 키워드 조합 필요 | ✅ "분위기 좋은 맛집" 가능 |
| 상업적 이용 | ✅ 무료 쿼터(일 10만 건) + 초과분 종량제 과금 | ✅ 유료 플랜으로 명확 |

### 최종 결정: 카카오 유지

Mobv는 교집합 영역 안에서 지역 정확도가 핵심이라 카카오가 더 적합. Google Places는 평점/사진이 강점이지만, 망원에서 홍대 맛집을 반환하는 등 지역 정확도가 낮아 교집합 기반 서비스와 맞지 않음.

Google Places는 추후 평점/사진 표시가 필요할 때 카카오와 병행 검토.

### 확인 필요 — 카카오맵 출처 표기

로컬 API 자체는 무료 쿼터 + 종량제 과금 구조라 상업적 이용에 별도 계약이 필요하지 않다. 다만 지도 SDK를 화면에 렌더링할 때 카카오 로고 노출이나 "Kakao Maps API를 활용하여..." 같은 출처 표기 의무가 있는지는 API 사용과 별개의 이슈이므로, 정식 출시 전 Kakao Developers 콘솔의 지도 SDK 이용약관을 확인해야 한다.