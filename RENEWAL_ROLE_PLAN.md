# Mobv 리뉴얼 역할 분담 계획

> 모두가 괜찮은 곳에서 만나요  
> Where everyone meets.

## 1. 리뉴얼 방향 요약

기존 Chemeet은 카카오톡 대화 파일 업로드와 GPT 기반 취향 분석을 중심으로 약속 장소를 추천했다. Mobv 리뉴얼에서는 진입장벽이 높은 업로드 과정을 제거하고, 사용자가 직접 지도에 "만나도 괜찮은 범위"를 원으로 표시하는 방식으로 전환한다.

핵심 기능은 다음 세 가지다.

| 기능 | 설명 |
| --- | --- |
| 선호 범위 원 그리기 | 각자가 지도에서 만나도 괜찮은 범위를 표시 |
| 날짜 조율 | 가능한 날짜와 시간대를 선택하고 교집합을 계산 |
| 장소 추천 | 모든 멤버의 원이 겹치는 구역을 기준으로 장소 10개 추천 |

이번 리뉴얼의 목표는 "어디가 가장 중간인가?"가 아니라 **"어디가 모두가 괜찮은 곳인가?"** 를 해결하는 것이다.

## 2. 전체 역할 원칙

두 명이 작업할 때는 단순히 프론트엔드/백엔드로만 나누기보다, **데이터 구조와 API 계약을 먼저 함께 정한 뒤 각자 구현**하는 방식이 좋다.

| 영역 | 주 담당 | 비고 |
| --- | --- | --- |
| Flutter 앱 플로우 | 프론트엔드 | 화면, 상태, 지도, 사용자 경험 |
| Flask 추천 API | 백엔드 | 교집합 계산, 장소 추천, 외부 API |
| Firestore 구조 | 공동 | 가장 먼저 합의 필요 |
| API 요청/응답 형식 | 공동 | 프론트/백엔드 병렬 작업의 기준 |
| Firebase Auth / Rules | 백엔드 중심, 프론트 협업 | 보안과 앱 로그인 흐름이 연결됨 |
| 출시 준비 | 프론트 중심, 공동 검수 | 브랜딩, 빌드, 스토어 자료 |

## 3. 개인별 핵심 책임

### 프론트엔드 담당

- Chemeet에서 Mobv로 앱 리브랜딩
- 카카오톡 업로드/분석 화면 제거
- 방 만들기, 초대 코드, 멤버 상태 UI 정리
- 날짜 다중 선택 및 시간대 선택 UI 구현
- 방장 날짜 확정 UI 구현
- 지도 원 그리기 UX 개선
- 모든 멤버 입력 완료 상태 표시
- 추천 장소 카드 UI 개선
- 교집합 없음 안내 및 원 재조정 플로우 구현
- 결과 공유 링크 화면 구현
- Android AAB 빌드 및 Play Store 등록 자료 준비

### 백엔드 담당

- 기존 `/analyze` API 제거 또는 비활성화
- 카카오톡 파서, OpenAI 분석, 친밀도 기반 반경 확장 제거
- `/recommend` API를 Mobv 구조에 맞게 개편
- 원 교집합 계산 로직 정리
- 교집합이 없을 때 중간지점 fallback 제거
- Google Places API 검토 및 프로토타입 구현
- 교집합 내 지하철역 기준 장소 검색 로직 검토
- Firebase ID Token 검증 추가
- Firestore Security Rules 초안 작성
- API 배포 환경 정리

### 공동 담당

- Firestore 문서 구조 확정
- room status 값 확정
- 날짜/시간대 데이터 모델 확정
- 추천 장소 데이터 모델 확정
- 방장 권한 기준 확정
- 베타 테스트 시나리오 작성
- 개인정보처리방침 작성
- 출시 전 최종 QA

## 4. 먼저 합의해야 할 공통 계약

개발을 시작하기 전에 아래 항목은 반드시 함께 정한다.

| 항목 | 결정해야 할 내용 |
| --- | --- |
| Firestore 구조 | `rooms`, `members`, `availabilities`, `circles`, `recommendations` 저장 방식 |
| room status | 방 상태값 목록과 전환 조건 |
| 날짜 모델 | 날짜, 시간대, 방장 확정값 저장 방식 |
| 원 모델 | 좌표, 반경, 사용자 정보 저장 방식 |
| 추천 API | 요청 JSON, 응답 JSON, 에러 포맷 |
| 장소 모델 | 이름, 주소, 좌표, 평점, 사진, 영업시간 필드 |
| 권한 | 방장만 가능한 작업, 멤버가 가능한 작업 |

## 5. 권장 Firestore 구조

```text
rooms/{roomId}
  createdBy
  inviteCode
  members
  memberNames
  category
  status
  maxMembers
  selectedDate
  selectedTimeSlot
  allDatesCompleted
  allCirclesCompleted
  createdAt
  updatedAt

rooms/{roomId}/availabilities/{uid}
  dates
  timeSlots
  updatedAt

rooms/{roomId}/circles/{uid}
  lat
  lng
  radius
  userName
  updatedAt

rooms/{roomId}/recommendations/{recommendationId}
  places
  center
  hasIntersection
  createdAt

rooms/{roomId}/history/{historyId}
  confirmedPlace
  appointmentDate
  members
  createdAt
```

## 6. 권장 room status

| 상태 | 의미 |
| --- | --- |
| `waiting` | 방 생성 후 멤버를 기다리는 상태 |
| `collecting` | 날짜와 원 입력을 받는 상태 |
| `dateReady` | 모든 멤버가 날짜를 입력한 상태 |
| `circleReady` | 모든 멤버가 원을 입력한 상태 |
| `recommended` | 장소 추천이 완료된 상태 |
| `confirmed` | 최종 장소가 확정된 상태 |

날짜 입력과 원 입력은 서로 독립적이므로, 실제 구현에서는 `status` 하나만으로 모든 상태를 표현하기보다 아래 Boolean 필드를 함께 두는 것이 좋다.

```text
allDatesCompleted
allCirclesCompleted
```

## 7. 추천 API 계약 예시

### 요청

```json
{
  "roomId": "abc123",
  "category": "cafe",
  "date": "2026-07-01",
  "timeSlot": "evening",
  "circles": [
    {
      "uid": "user1",
      "lat": 37.5665,
      "lng": 126.978,
      "radius": 2000
    },
    {
      "uid": "user2",
      "lat": 37.55,
      "lng": 126.99,
      "radius": 2500
    }
  ]
}
```

### 응답

```json
{
  "hasIntersection": true,
  "center": {
    "lat": 37.5665,
    "lng": 126.978
  },
  "searchRadius": 1500,
  "places": [
    {
      "id": "place_id",
      "name": "카페 이름",
      "address": "서울 ...",
      "lat": 37.56,
      "lng": 126.97,
      "rating": 4.5,
      "photoUrl": "https://...",
      "openNow": true
    }
  ]
}
```

### 교집합이 없을 때

```json
{
  "hasIntersection": false,
  "message": "겹치는 지역이 없어요. 조금 더 넓게 선택해보세요.",
  "places": []
}
```

## 8. 6-8주 개발 일정

### 1주차: 레거시 제거와 구조 확정

| 담당 | 작업 |
| --- | --- |
| 프론트엔드 | 업로드/분석 화면 제거, Mobv 브랜딩 적용, 방 생성 플로우 정리 |
| 백엔드 | `/analyze` 제거 범위 확인, Google Places 프로토타입, `/recommend` 개편 설계 |
| 공동 | Firestore 구조, status, API 계약 확정 |

### 2-3주차: 날짜 조율 기능

| 담당 | 작업 |
| --- | --- |
| 프론트엔드 | 날짜 선택 UI, 시간대 선택 UI, 멤버별 입력 상태, 방장 확정 화면 |
| 백엔드 | 날짜 교집합 규칙 검토, Firestore Rules 초안, 필요 시 날짜 계산 API |
| 공동 | 전원 입력 완료 기준, 방장 권한 기준 확정 |

### 4-5주차: 원 교집합과 장소 추천

| 담당 | 작업 |
| --- | --- |
| 프론트엔드 | 원 그리기 UX 개선, 완료 상태 감지, 추천 카드 UI, 교집합 없음 UX |
| 백엔드 | 교집합 계산, 장소 추천 API, 지하철역 기준 검색, Places 응답 정규화 |
| 공동 | 추천 품질 테스트, 실패 케이스 점검 |

### 6주차: 공유 링크와 히스토리

| 담당 | 작업 |
| --- | --- |
| 프론트엔드 | 결과 공유 화면, 공유 링크 라우트, 장소 확정 UI, 히스토리 화면 정리 |
| 백엔드 | 공유 링크용 데이터 접근 방식, public read 범위 검토, 토큰 검증 |
| 공동 | 실제 약속 시나리오 테스트 |

### 7-8주차: 출시 준비

| 담당 | 작업 |
| --- | --- |
| 프론트엔드 | AAB 빌드, 앱 아이콘, 스토어 스크린샷, 앱 설명 작성 |
| 백엔드 | 배포 환경 점검, Rate Limit, App Check 검토 |
| 공동 | 개인정보처리방침, 계정 삭제 기능, 베타 테스트, 최종 QA |

## 9. 우선순위

### P0: 출시 전 필수

- 카카오톡 업로드/GPT 분석 제거
- 날짜 조율 기능
- 원 그리기 및 교집합 계산
- 장소 추천 10개 제공
- 교집합 없음 처리
- Firebase Auth
- Firestore Security Rules
- 계정 삭제 기능
- 개인정보처리방침
- Android AAB 빌드

### P1: 있으면 좋은 기능

- Google Places 사진/평점/영업시간 표시
- 결과 공유 링크
- 히스토리 저장
- Firebase App Check
- API Rate Limit
- 추천 장소 정렬 고도화

### P2: 출시 후 개선

- iOS 출시
- 예약 플랫폼 연동
- 추천 이유 설명
- 사용자 피드백 기반 추천 개선
- 도메인 연결 및 웹 결과 페이지 고도화

## 10. 작업 방식 제안

### 브랜치 전략

```text
main
feature/frontend-renewal
feature/backend-recommend-api
feature/date-coordination
feature/share-result
```

두 명이 동시에 같은 파일을 오래 만지지 않도록 기능 단위로 브랜치를 나눈다.

### 매주 확인할 것

- 이번 주 완료한 기능
- 다음 주 작업할 기능
- Firestore 구조 변경 여부
- API 요청/응답 변경 여부
- 프론트에서 막힌 백엔드 이슈
- 백엔드에서 필요한 프론트 입력값

### PR 또는 머지 전 체크리스트

- 앱이 실행되는가
- 기존 방 생성/입장 흐름이 깨지지 않았는가
- Firestore 필드명이 문서와 일치하는가
- API 응답이 프론트 모델과 일치하는가
- 실패 케이스가 사용자에게 안내되는가
- 보안상 누구나 모든 방을 읽을 수 있는 구조는 아닌가

## 11. 최종 정리

이번 리뉴얼에서 프론트엔드는 사용자가 실제로 약속을 만들고 조율하는 경험을 책임지고, 백엔드는 추천 품질과 보안, 외부 API 연동을 책임진다.

가장 중요한 공동 작업은 Firestore 구조와 API 계약이다. 이 두 가지를 먼저 고정하면 두 명이 병렬로 개발해도 충돌이 훨씬 줄어든다.

추천 역할 요약:

| 담당 | 핵심 오너십 |
| --- | --- |
| 프론트엔드 | 앱 플로우, 지도/날짜 UX, 결과 화면, 출시 빌드 |
| 백엔드 | 추천 API, 교집합 계산, 장소 API, 보안 |
| 공동 | Firestore 구조, API 계약, QA, 출시 판단 |
