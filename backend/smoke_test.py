"""
Mobv 백엔드 — 4개 카테고리 최종 스모크 테스트

test_recommend.py(48개)는 전부 mock이라 로직만 검증합니다.
이건 실제 카카오/OpenWeather API를 진짜로 호출해서, 깃에 올리기 전
마지막으로 눈으로 확인하기 위한 스크립트입니다. assert가 아니라 출력 위주라,
결과 좋고 나쁨은 사람이 보고 판단합니다.

사전 준비:
- backend 폴더 안에서 실행 (recommend/ 패키지를 찾아야 함)
- .env에 KAKAO_REST_KEY, OPENWEATHER_API_KEY 설정되어 있어야 함
- 서버를 따로 띄울 필요 없음 (Flask test client가 내부적으로 호출)

실행: python smoke_test.py
"""
import json

import app as app_module

app_module.app.config["TESTING"] = True
client = app_module.app.test_client()

# 실제로 겹치는 2인 시나리오 (서울시청 근처, 반경 1.5km씩)
USERS = [
    {"lat": 37.5665, "lng": 126.9780, "radius": 1500},
    {"lat": 37.5675, "lng": 126.9790, "radius": 1500},
]

CATEGORIES = ["cafe", "restaurant", "bar", "study"]

results = {}

for category in CATEGORIES:
    print(f"\n{'=' * 60}")
    print(f"카테고리: {category}")
    print("=" * 60)

    res = client.post("/recommend", json={"users": USERS, "category": category})
    body = res.get_json()

    if res.status_code != 200:
        print(f"❌ 실패 (status {res.status_code}): {body}")
        results[category] = "FAIL"
        continue

    if not body.get("hasIntersection"):
        print(f"⚠️  교집합 없음: {body.get('message')}")
        results[category] = "NO_INTERSECTION"
        continue

    places = body.get("places", [])
    print(f"area_name: {body.get('area_name')}  |  장소 {len(places)}개  |  날씨: {body.get('weather')}")
    for p in places[:8]:
        print(f"  - {p['name']:<20} | {p['category']:<40} | {p['distance']}m")

    if len(places) < 2:
        print("⚠️  장소가 2곳 미만 (422가 났어야 할 수도 있음)")
        results[category] = "TOO_FEW"
    else:
        results[category] = "OK"

print(f"\n{'=' * 60}")
print("전체 요약")
print("=" * 60)
for category, status in results.items():
    mark = "✅" if status == "OK" else "⚠️ " if status != "FAIL" else "❌"
    print(f"  {mark} {category:<12} {status}")

all_ok = all(v == "OK" for v in results.values())
print("\n" + ("✅ 4개 카테고리 전부 정상" if all_ok else "⚠️  위에서 OK가 아닌 항목을 직접 확인해보세요"))