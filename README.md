# Mobv

> 모두가 괜찮은 곳에서 만나요  
> Where everyone meets.

Mobv는 여러 명이 약속 장소를 정할 때 각자가 지도에서 "만나도 괜찮은 범위"를 원으로 표시하고, 그 원들이 겹치는 구역을 기준으로 장소를 추천받는 Flutter 앱입니다.

## 리뉴얼 방향

- Chemeet에서 Mobv로 리브랜딩
- 카카오톡 대화 파일 업로드 제거
- GPT/OpenAI 대화 분석 제거
- 친밀도 점수 기반 추천 제거
- 사용자가 지도에서 직접 이동 가능 범위를 원으로 입력
- 멤버별 원 교집합 기반 장소 추천
- 날짜 조율과 결과 공유 기능 추가
- Android 앱 중심의 포트폴리오 완성도 강화

## 기술 스택

- Flutter / Dart
- Firebase Auth
- Cloud Firestore
- Flask 추천 API
- Kakao Map / Local API

## 주요 구조

```text
lib/
  screens/      Flutter 화면
  services/     Firebase 및 API 연동
  widgets/      공통 UI 위젯

backend/
  app.py        Flask API
  recommend/    장소 추천 관련 로직
```

## 1주차 작업 범위

- Mobv 앱 이름과 웹 메타데이터 정리
- 방 생성 플로우에서 카카오톡 파일 업로드 제거
- 분석 화면과 분석 서비스 제거
- Firestore 방 생성 필드를 Mobv 권장 구조에 맞게 보강
- 민감 정보와 로컬 설정 파일이 Git에 올라가지 않도록 `.gitignore` 정리

## 실행

```bash
flutter pub get
flutter run
```

로컬 API 주소나 지도 키는 `.env` 대신 `--dart-define` 또는 로컬 전용 설정으로 주입하는 것을 권장합니다.
