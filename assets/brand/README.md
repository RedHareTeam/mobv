# Mobv — 프론트엔드 전달 패키지 (Flutter)

> 모두가 괜찮은 곳에서 만나요 — Where everyone meets.

## 파일 목록

| 파일 | 용도 |
|------|------|
| `mobv-wordmark.png` | 가로형 워드마크 (투명, 918×287). 앱바·스플래시·헤더 |
| `mobv-symbol.svg` / `.png` | 심볼 마크(두 원). 벡터 + 투명 PNG |
| `mobv-app-icon.svg` / `.png` | 앱 아이콘 (1024×1024, 흰 배경) |
| `app_colors.dart` | 컬러 토큰 (`Color(0xFF…)`) |
| `mobv_logo.dart` | 로고 위젯 (`MobvWordmark`, `MobvSymbol`) |
| `Mobv 브랜드 핸드오프.dc.html` | 기획안 첨부용 1페이지 가이드 (브라우저에서 열기 / PDF 출력) |

## 컬러

| 토큰 | HEX | Flutter |
|------|-----|---------|
| Primary · Indigo | `#5865F2` | `Color(0xFF5865F2)` |
| Secondary · Mint | `#5AD6C0` | `Color(0xFF5AD6C0)` |
| Accent · Teal | `#2E9BC8` | `Color(0xFF2E9BC8)` |
| Title | `#1C2350` | `Color(0xFF1C2350)` |
| Body | `#3A4170` | `Color(0xFF3A4170)` |
| Muted | `#9AA0BD` | `Color(0xFF9AA0BD)` |
| Border | `#E6E8F0` | `Color(0xFFE6E8F0)` |
| Background | `#F4F5F8` | `Color(0xFFF4F5F8)` |
| Surface | `#FFFFFF` | `Color(0xFFFFFFFF)` |

## 타이포

- 워드마크 / 영문: **Poppins** (600–700)
- 한글 본문: **Pretendard** 권장

## 적용 (Flutter)

```yaml
# pubspec.yaml
dependencies:
  flutter_svg: ^2.0.0

flutter:
  assets:
    - assets/brand/mobv-wordmark.png
    - assets/brand/mobv-symbol.svg
```

```dart
import 'mobv_logo.dart';

AppBar(title: const MobvWordmark(height: 26));
const MobvSymbol(size: 32);
```

## 규칙

- 두 원의 색·겹침 비율은 변경하지 마세요 (브랜드 핵심).
- 심볼 보호 여백: 원 지름의 50% 이상.
- 워드마크 최소 폭: 96px.
