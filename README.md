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

## 향후 계획 

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

1. 정직한 계산만 한다 
2. 서버가 사용자의 선택을 임의로 바꾸지 않는다
3. 누구도 지목하지 않는다
4. 공정성 도구다 — 한 사람이 부담을 몰아서 지지 않게 한다
5. 교집합 = 모두가 허용한 구역 

새 기능 추가 전에 이 원칙과 충돌하는지 먼저 확인하세요.
# Mobv Frontend

> 모두가 괜찮은 곳에서 만나요  
> Where everyone meets.

Mobv의 프론트엔드는 여러 멤버가 약속 장소를 정할 때, 각자가 지도 위에서 만날 수 있는 이동 범위를 원으로 설정하고 교집합 구역 기반의 추천 장소를 시각적으로 조율할 수 있는 **Flutter 기반 크로스 플랫폼(Web & Mobile) 클라이언트**입니다.

---

## 📱 Frontend Overview

- **프레임워크**: Flutter (Dart 3.11+)
- **지원 플랫폼**: Web (Chrome 우선 최적화), Mobile (Android / iOS)
- **핵심 경험**:
  - 직관적인 인터랙티브 지도 범위(원) 드로잉 & 실시간 다자간 동기화
  - Glassmorphism 기반의 모던하고 일관된 디자인 시스템
  - Web/Mobile 공통 카카오맵 JavaScript SDK 브리지 아키텍처
  - 날짜 조율 타임테이블 매트릭스, 추천 장소 카드 캐러셀 및 투표 시스템
  - 확정된 방문 기록을 시각화하는 인터랙티브 히트맵

---

## 🛠 Tech Stack & Libraries

| 분류 | 기술 / 라이브러리 | 설명 |
|------|------------------|------|
| **Core** | `Flutter`, `Dart` | 크로스플랫폼 UI 프레임워크 |
| **BaaS / Client** | `firebase_core`, `firebase_auth`, `cloud_firestore` | 인증 및 실시간 데이터 스트림 구독 |
| **Map & Location** | `Kakao Map JS SDK`, `webview_flutter`, `geolocator` | 웹/모바일 양방향 지도 렌더링 및 현재 위치 감지 |
| **Web Integration** | `pointer_interceptor` | Flutter Web 환경에서 지도 IFrame 위 UI 오버레이 클릭 보장 |
| **Network & Utility** | `http`, `url_launcher`, `uuid`, `flutter_dotenv` | 백엔드 추천 API 통신 및 외부 링크 연동 |
| **UI & Assets** | `flutter_svg`, `Pacifico Font` | 벡터 그래픽 및 브랜드 커스텀 타이포그래피 |

---

## 📂 Directory Structure

```text
lib/
├── app_config.dart             # 환경 변수 및 Dart Define 설정 주입
├── app_theme.dart              # 색상 팔레트, Glassmorphism, 텍스트/버튼 테마
├── constants.dart              # 앱 전역 상수
├── firebase_options.dart       # Firebase 클라이언트 초기화 옵션
├── main.dart                   # 앱 엔트리포인트 및 글로벌 테마/라우트 설정
│
├── models/
│   └── date_coordination_model.dart  # 날짜/시간대 조율 데이터 모델
│
├── screens/                    # 핵심 화면 UI
│   ├── splash_screen.dart             # 초기 진입 스플래시 화면
│   ├── auth_screen.dart               # 이메일 로그인 / 회원가입 화면
│   ├── home_screen.dart               # 대시보드 (진행 중인 약속, 히스토리, 참여 모달)
│   ├── create_appointment_screen.dart # 새 약속 생성 (타이틀, 인원, 카테고리, 후보 일정)
│   ├── date_coordination_screen.dart  # 멤버별 참여 가능 일정 인터랙티브 매트릭스
│   ├── map_screen.dart                # 인터랙티브 카카오맵 범위 설정 & 교집합 확인
│   ├── place_screen.dart              # 추천 장소 확인, 카카오맵 상세 보기 및 실시간 투표
│   └── heatmap_screen.dart            # 지난 약속 방문 장소 분포 히트맵 & 기록
│
├── services/                   # 비즈니스 로직 & Firestore 스트림 서비스
│   ├── auth_service.dart              # Firebase Auth 기반 사용자 로그인/세션
│   ├── appointment_service.dart       # 약속 CRUD, 상태(Status) 흐름 관리
│   ├── circle_service.dart            # 지도 위 멤버별 좌표/반경 데이터 동기화
│   ├── vote_service.dart              # 추천 장소 투표 관리
│   └── history_service.dart           # 확정된 약속 방문 히스토리 및 리뷰 조회
│
└── widgets/                    # 재사용 가능한 UI 컴포넌트
    ├── kakao_map_webview.dart         # 지도 컨트롤러 및 브리지 래퍼
    ├── platform_html_view.dart        # 조건부 익스포트 인터페이스
    ├── platform_html_view_web.dart    # Web IFrameElement 기반 지도 렌더러
    ├── platform_html_view_mobile.dart # Mobile InApp WebView 기반 지도 렌더러
    ├── glassmorphic_container.dart    # 블러 & 반투명 배경 컨테이너
    ├── glass_popup_menu.dart          # 글래스 스타일 팝업 메뉴
    ├── app_dialog.dart                # 공통 다이얼로그
    ├── gradient_button.dart           # 브랜드 그라디언트 액션 버튼
    ├── mobv_brand.dart                # 로고 및 심볼 위젯
    ├── screen_header.dart             # 공통 상단 헤더
    └── no_intersection_sheet.dart     # 범위 미교집합 시 안내 바텀시트

web/
├── kakao_map_bridge.html       # 지도 드로잉 & Flutter-JS postMessage 브리지
└── heatmap_bridge.html         # 히트맵 렌더링 JS 브리지

assets/
├── brand/                      # Mobv 심볼, 워드마크, 앱 아이콘
└── fonts/                      # Pacifico 서체
```

---

## 🎨 Design System (`AppTheme`)

- **Primary Tone**: 세련된 Modern Black (`#18181B`) & Crisp White 기반의 미니멀리즘
- **Point & Member Colors**:
  - 각 사용자에게 고유한 프로필 컬러(`profileColor`)가 부여되며, 지도 원·아바타·상태 칩에 공통 반영
- **Glassmorphism & Overlay**:
  - 지도 위 UI 요소는 `GlassmorphicContainer`를 적용하여 맵 가시성을 유지하면서 부드러운 블러 효과 제공
  - Flutter Web 환경에서 IFrame 위에 뜨는 다이얼로그나 모달을 누를 수 있도록 `PointerInterceptor` 적용

---

## 🗺️ Screen Flow & Key Features

```mermaid
graph TD
    Splash[Splash Screen] --> Auth[Auth Screen]
    Auth --> Home[Home Screen]
    Home --> Create[Create Appointment]
    Home --> JoinModal[초대 코드로 참여]
    Home --> Heatmap[Heatmap Screen]
    
    Create --> DateCoord[Date Coordination]
    JoinModal --> DateCoord
    DateCoord --> Map[Map Screen - 범위 입력]
    Map --> Place[Place Screen - 장소 투표]
    Place --> Confirmed[약속 확정]
    Confirmed --> Home
```

1. **로그인 / 가입 (`auth_screen.dart`)**
   - 이메일 기반 간편 인증 및 프로필 컬러 자동 생성
2. **홈 대시보드 (`home_screen.dart`)**
   - 내가 참여한 진행 중인 약속 카드 목록 (상태별 배지 표시)
   - 플로팅 버튼을 통한 새 약속 생성 및 6자리 초대 코드로 참여 다이얼로그
   - 지난 발자취를 볼 수 있는 히트맵 진입 버튼
3. **약속 생성 (`create_appointment_screen.dart`)**
   - 약속명, 카테고리(카페, 식당 등), 최대 참여 인원 설정
   - 일정 조율이 필요한 경우 후보 날짜 및 시간대 다중 지정
4. **일정 조율 (`date_coordination_screen.dart`)**
   - 멤버별 가능/불가능 시간대를 인터랙티브한 그리드 칩으로 입력
   - 참여자 전원의 겹치는 최적 시간대를 실시간 집계하여 표시
5. **지도 범위 설정 (`map_screen.dart`)**
   - 카카오맵 위에서 내 위치를 중심으로 반경 조절 원 그리기
   - Firestore 실시간 리스너를 통해 다른 멤버들이 그린 원이 실시간 렌더링
   - 교집합 구역이 생성되면 추천 버튼 활성화 (`_MapRecommendFloatingButton`)
6. **장소 투표 & 확정 (`place_screen.dart`)**
   - 교집합 구역 기반 추천 장소 리스트 카드
   - 장소별 카카오맵 상세 정보 보기 및 멤버 실시간 투표 현황 반영
   - 투표 종료 후 최종 만남 장소 확정
7. **방문 히트맵 (`heatmap_screen.dart`)**
   - 과거 확정되었던 모임 장소들의 누적 분포를 카카오맵 히트맵으로 시각화
   - 장소별 방문 일자 및 작성된 메모/후기 타임라인 열람

---

## 🌉 Cross-Platform Map Bridge Architecture

Flutter Web과 Mobile 환경에서 카카오맵 JavaScript SDK를 동일하게 구동하기 위해 **플랫폼별 브리지 패턴**을 사용합니다.

- **Flutter Web**:
  - `web/kakao_map_bridge.html`을 `IFrameElement`로 로드
  - `window.addEventListener('message')`를 통해 Flutter와 JS 간 양방향 이벤트 통신 (원 생성, 반경 변경, 중심 이동, 교집합 영역 전달 등)
  - 웹 브라우저에서 Flutter 터치 이벤트를 맵 레이어에 가로채이지 않도록 `PointerInterceptor`로 위젯 레이어 감싸기
- **Flutter Mobile**:
  - `webview_flutter`를 통해 로컬 에셋 HTML 및 JS SDK 구동
  - `JavaScriptChannel`을 통한 네이티브-웹뷰 통신

---

## ⚙️ Frontend Environment Setup

### 1. Dart Defines 설정

웹 환경 실행 시 필요한 카카오 자바스크립트 키와 백엔드 주소는 `.dart_defines/web.json`에 정의합니다.

`.dart_defines/web.example.json`을 복사하여 `.dart_defines/web.json` 파일을 생성합니다:

```json
{
  "KAKAO_JS_KEY": "YOUR_KAKAO_JAVASCRIPT_KEY",
  "BASE_URL": "http://localhost:5000"
}
```

> **주의**: `.dart_defines/web.json` 및 Firebase 비공개 설정 파일은 보안상 Git 저장소에 커밋하지 않습니다.

### 2. Kakao Developers 허용 도메인 등록

Flutter Web 실행 시 포트를 고정하여 개발합니다:
- 개발용 로컬 주소: `http://localhost:5555`
- [Kakao Developers 콘솔](https://developers.kakao.com)의 **내 애플리케이션 > 플랫폼 > Web**에 `http://localhost:5555`를 등록해야 지도가 정상 표시됩니다.

---

## 🚀 How to Run

### 의존성 패키지 설치
```bash
flutter pub get
```

### Flutter Web 실행 (포트 고정)
```bash
flutter run -d chrome --web-port 5555 --dart-define-from-file=.dart_defines/web.json
```

### Android / iOS 모바일 실행
```bash
flutter run
```

### VS Code Debugging
`.vscode/launch.json`에 정의된 프리셋을 통해 원클릭 디버깅이 가능합니다:
- `Mobv Web (Chrome, port 5555)`
- `Mobv Web Debug (Chrome, port 5555)`
- `Mobv Android`

---

## 🧪 Code Quality & Linter

코드 정적 분석:
```bash
flutter analyze
```
