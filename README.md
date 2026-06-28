# Mobv

> 모두가 괜찮은 곳에서 만나요  
> Where everyone meets.

Mobv는 여러 명이 약속 장소를 정할 때 각자가 지도에서 "만나도 괜찮은 범위"를 원으로 표시하고, 멤버들의 원이 겹치는 구역을 기준으로 장소를 추천받는 Flutter 앱입니다.

## Overview

Mobv는 기존 대화 분석 기반 추천 흐름을 제거하고, 사용자가 직접 입력한 위치 범위와 약속 정보를 중심으로 장소를 정하는 앱입니다.

핵심 흐름은 다음과 같습니다.

1. 약속 생성
2. 초대 코드 또는 공유 링크로 멤버 참여
3. 각 멤버가 지도에서 만날 수 있는 범위 입력
4. 모든 멤버의 범위가 겹치는 구역을 기준으로 장소 추천
5. 추천 장소 투표
6. 최종 장소 확정
7. 확정된 약속과 방문 기록을 히트맵에서 확인

## Features

- 이메일 기반 로그인
- 약속 생성 및 초대 코드 참여
- 사용자별 프로필 색상 시스템
- Kakao Map 기반 범위 그리기
- 멤버별 범위 입력 상태 표시
- 원 교집합 기반 장소 추천
- 추천 장소 투표 및 최종 확정
- 확정된 약속 목록 관리
- 방문 기록 기반 히트맵

## Tech Stack

- Flutter / Dart
- Firebase Auth
- Cloud Firestore
- Kakao Map JavaScript SDK
- Kakao Local API
- Flask recommendation API

## Project Structure

```text
lib/
  screens/      앱 화면
  services/     Firebase, 인증, 투표, 약속 데이터 서비스
  widgets/      공통 UI와 지도 WebView 브리지

assets/
  brand/        Mobv 로고, 앱 아이콘, 브랜드 컬러 자료
  fonts/        앱 폰트

backend/        Flask 추천 API

web/
  kakao_map_bridge.html
  heatmap_bridge.html
```

## Environment

로컬 실행에 필요한 키와 URL은 Git에 올리지 않습니다.

웹 실행용 dart define 예시는 다음 파일을 참고합니다.

```text
.dart_defines/web.example.json
```

실제 로컬 실행 파일은 아래 경로에 생성합니다.

```text
.dart_defines/web.json
```

예시:

```json
{
  "KAKAO_JS_KEY": "YOUR_KAKAO_JAVASCRIPT_KEY",
  "BASE_URL": "http://localhost:5000"
}
```

주의:

- `.dart_defines/web.json`은 Git에 올라가지 않습니다.
- `.env` 파일도 Git에 올라가지 않습니다.
- Firebase 설정 파일과 Google service config도 Git에 올리지 않습니다.

## Kakao Setup

Flutter Web에서 Kakao Map을 테스트할 때는 실행 포트를 고정하는 것이 편합니다.

현재 개발용 웹 포트:

```text
http://localhost:5555
```

Kakao Developers의 JavaScript 키 허용 도메인에 위 주소를 등록합니다.

## Run

의존성 설치:

```bash
flutter pub get
```

웹 실행:

```bash
flutter run -d chrome --web-port 5555 --dart-define-from-file=.dart_defines/web.json
```

Android 실행:

```bash
flutter run
```

VS Code에서는 `.vscode/launch.json`의 다음 실행 구성을 사용할 수 있습니다.

- `Mobv Web (Chrome, port 5555)`
- `Mobv Web Debug (Chrome, port 5555)`
- `Mobv Android`

## Firebase

사용 중인 Firebase 기능:

- Firebase Auth
- Cloud Firestore

Firestore는 약속 중심 구조를 사용합니다.

```text
users/{uid}
appointments/{appointmentId}
  circles/{uid}
  votes/{uid}
  history/{historyId}
    records/{recordId}
```

### users/{uid}

사용자 기본 정보와 내가 참여한 약속 id 목록을 저장합니다.

```js
{
  email: string,
  userName: string,
  profileColor: number,      // 0xAARRGGBB 형식의 Flutter color int
  appointments: string[],    // 참여 중이거나 확정 기록을 가진 appointmentId 목록
  createdAt: Timestamp
}
```

`profileColor`는 프로필 아바타, 지도 원 색상, 멤버 표시 chip에 함께 사용합니다.

### appointments/{appointmentId}

약속의 기본 정보, 참여자, 추천/확정 상태를 저장합니다.

```js
{
  createdBy: string,         // 약속 생성자 uid
  members: string[],         // 참여자 uid 목록
  memberProfiles: {
    [uid]: {
      name: string,
      color: number
    }
  },

  status: string,            // waiting | drawing | circleReady | voting | confirmed
  inviteCode: string,        // 6자리 초대 코드
  appointmentTitle: string,
  category: string,          // 예: cafe
  maxMembers: number,

  appointmentDate: Timestamp,

  places: Place[],           // 장소 추천 이후 임시 저장
  confirmedPlace: Place,     // 최종 확정 장소

  selectedDate: string | null,
  selectedTimeSlot: string | null,
  allDatesCompleted: boolean,
  allCirclesCompleted: boolean,

  createdAt: Timestamp,
  updatedAt: Timestamp
}
```

현재 앱에서 사용하는 주요 status:

| status | 의미 |
|--------|------|
| `waiting` | 약속 생성 후 참여자를 기다리는 상태 |
| `drawing` | 멤버들이 만날 수 있는 범위를 입력하는 상태 |
| `circleReady` | 범위 입력이 완료된 상태 |
| `voting` | 추천 장소가 저장되고 장소 선택/투표 중인 상태 |
| `confirmed` | 최종 장소가 확정된 상태 |

참여 가능 상태:

```text
waiting, drawing, circleReady
```

`voting` 이후에는 새 멤버 참여를 막습니다.

### appointments/{appointmentId}/circles/{uid}

각 멤버가 지도에서 입력한 원 범위를 저장합니다.

```js
{
  lat: number,
  lng: number,
  radius: number,            // meter
  userName: string,
  updatedAt: Timestamp
}
```

문서 id는 사용자의 `uid`입니다.

### appointments/{appointmentId}/votes/{uid}

장소 선택 화면에서 각 멤버가 고른 장소를 저장합니다.

```js
{
  userId: string,
  userName: string,
  selectedPlaceId: string    // place.kakaoId
}
```

문서 id는 사용자의 `uid`입니다.

### appointments/{appointmentId}/history/{historyId}

최종 확정된 약속 기록을 저장합니다. 히트맵은 이 데이터를 기준으로 표시됩니다.

```js
{
  confirmedPlace: Place,
  members: string[],
  appointmentDate: Timestamp,
  date: Timestamp
}
```

`historyId`는 같은 확정 결과가 중복 저장되지 않도록 `placeId_timestamp` 형식으로 생성합니다.

### appointments/{appointmentId}/history/{historyId}/records/{recordId}

확정된 방문 기록에 남기는 간단한 후기/메모입니다.

```js
{
  userId: string,
  userName: string,
  review: string,
  createdAt: Timestamp
}
```

### Place Object

추천/확정 장소는 Kakao 장소 데이터를 앱에서 쓰기 좋은 형태로 저장합니다.

```js
{
  kakaoId: string,
  name: string,
  address: string,
  lat: number,
  lng: number,
  category: string,
  url: string,
  kakaoUrl: string
}
```

### 확정 이후 정리되는 데이터

장소가 확정되면 확정 기록은 `history`에 저장하고, 약속 문서에서는 진행 중에만 필요한 임시 데이터를 정리합니다.

정리 대상:

```text
places
selectedDate
selectedTimeSlot
allDatesCompleted
allCirclesCompleted
maxMembers
historySaved
circles/*
votes/*
messages/*
```

이후 홈 화면에서는 `confirmedPlace`와 `appointmentDate`를 기준으로 다가오는 약속을 표시하고, 히트맵에서는 `history` 데이터를 사용합니다.