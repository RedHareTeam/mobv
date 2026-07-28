import requests

url = "http://localhost:5000/recommend"

categories = ["카페", "맛집", "술집", "디저트", "라멘", "파스타", "피자", "초밥", "고기", "국밥", "마라탕"]

def test(title, users, category="카페"):
    data = {"users": users, "category": category}
    response = requests.post(url, json=data)
    result = response.json()

    if not result.get('hasIntersection'):
        print(f"  NO 교집합 없음 — {result.get('message', '')}")
        return

    places = result.get('places', [])
    area = result.get('area_name', '알 수 없음')
    radius = result.get('search_radius', 0)
    print(f"  OK {area} | 반경 {radius}m | {len(places)}개")
    for p in places[:2]:
        print(f"     - {p['name']} | {p['category']}")

def section(title):
    print(f"\n{'='*55}")
    print(f"  {title}")
    print(f"{'='*55}")

# ── 1. 지역별 테스트 (카페 기준) ──────────────────────────
section("1. 지역별 테스트 (카페)")

LOCATIONS = [
    ("홍대~신촌",   [{"lat":37.5573,"lng":126.9245,"radius":3000}, {"lat":37.5443,"lng":126.9526,"radius":3000}]),
    ("강남~잠실",   [{"lat":37.4979,"lng":127.0276,"radius":3000}, {"lat":37.5133,"lng":127.1001,"radius":3000}]),
    ("홍대~강남",   [{"lat":37.5573,"lng":126.9245,"radius":4000}, {"lat":37.4979,"lng":127.0276,"radius":4000}]),
    ("성수~건대",   [{"lat":37.5444,"lng":127.0557,"radius":3000}, {"lat":37.5403,"lng":127.0704,"radius":3000}]),
    ("이태원~한남", [{"lat":37.5344,"lng":126.9944,"radius":2000}, {"lat":37.5281,"lng":127.0013,"radius":2000}]),
    ("망원~연남",   [{"lat":37.5560,"lng":126.9101,"radius":2000}, {"lat":37.5632,"lng":126.9244,"radius":2000}]),
    ("을지로~충무로",[{"lat":37.5663,"lng":126.9877,"radius":2000}, {"lat":37.5612,"lng":126.9947,"radius":2000}]),
]

for name, users in LOCATIONS:
    print(f"\n[{name}]")
    test(name, users, "카페")

# ── 2. 카테고리별 테스트 (홍대~신촌 기준) ─────────────────
section("2. 카테고리별 테스트 (홍대~신촌)")

users_base = [
    {"lat":37.5573,"lng":126.9245,"radius":3000},
    {"lat":37.5443,"lng":126.9526,"radius":3000},
]

for cat in categories:
    print(f"\n[{cat}]")
    test("홍대~신촌", users_base, cat)

# ── 3. 인원별 테스트 (교집합 없음 케이스 — 신설동 방향 3번째 좌표) ──
section("3. 인원별 테스트 — 교집합 없음 케이스 (홍대 기준, 카페)")

print("\n[2명]")
test("2명", [
    {"lat":37.5573,"lng":126.9245,"radius":3000},
    {"lat":37.5443,"lng":126.9526,"radius":3000},
], "카페")

print("\n[3명]")
test("3명", [
    {"lat":37.5573,"lng":126.9245,"radius":3000},
    {"lat":37.5443,"lng":126.9526,"radius":3000},
    {"lat":37.5326,"lng":126.9900,"radius":3000},
], "카페")

print("\n[4명]")
test("4명", [
    {"lat":37.5573,"lng":126.9245,"radius":3000},
    {"lat":37.5443,"lng":126.9526,"radius":3000},
    {"lat":37.5326,"lng":126.9900,"radius":3000},
    {"lat":37.5500,"lng":126.9700,"radius":3000},
], "카페")

print("\n[5명]")
test("5명", [
    {"lat":37.5573,"lng":126.9245,"radius":3000},
    {"lat":37.5443,"lng":126.9526,"radius":3000},
    {"lat":37.5326,"lng":126.9900,"radius":3000},
    {"lat":37.5500,"lng":126.9700,"radius":3000},
    {"lat":37.5620,"lng":126.9500,"radius":3000},
], "카페")

# ── 3-2. 인원별 테스트 (정상 교집합 케이스 — 신촌 생활권 좌표) ──
section("3-2. 인원별 테스트 — 정상 교집합 케이스 (신촌 생활권, 카페)")

print("\n[3명_정상]")
test("3명_정상", [
    {"lat":37.5573,"lng":126.9245,"radius":3000},  # 홍대입구역
    {"lat":37.5443,"lng":126.9526,"radius":3000},  # 신촌
    {"lat":37.5567,"lng":126.9463,"radius":3000},  # 이대역
], "카페")

print("\n[4명_정상]")
test("4명_정상", [
    {"lat":37.5573,"lng":126.9245,"radius":3000},  # 홍대입구역
    {"lat":37.5443,"lng":126.9526,"radius":3000},  # 신촌
    {"lat":37.5567,"lng":126.9463,"radius":3000},  # 이대역
    {"lat":37.5665,"lng":126.9388,"radius":3000},  # 연세대 정문
], "카페")

print("\n[5명_정상]")
test("5명_정상", [
    {"lat":37.5573,"lng":126.9245,"radius":3000},  # 홍대입구역
    {"lat":37.5443,"lng":126.9526,"radius":3000},  # 신촌
    {"lat":37.5567,"lng":126.9463,"radius":3000},  # 이대역
    {"lat":37.5665,"lng":126.9388,"radius":3000},  # 연세대 정문
    {"lat":37.5519,"lng":126.9268,"radius":3000},  # 서강대역
], "카페")

# ── 4. 반경 크기별 테스트 ─────────────────────────────────
section("4. 반경 크기별 테스트 (홍대~강남, 라멘)")

for r in [1000, 2000, 3000, 5000, 8000]:
    print(f"\n[반경 {r}m]")
    test(f"반경{r}", [
        {"lat":37.5573,"lng":126.9245,"radius":r},
        {"lat":37.4979,"lng":127.0276,"radius":r},
    ], "라멘")

# ── 5. 엣지 케이스 ────────────────────────────────────────
section("5. 엣지 케이스")

print("\n[교집합 없음 — 서울 vs 부산]")
test("서울vs부산", [
    {"lat":37.5665,"lng":126.9780,"radius":2000},
    {"lat":35.1796,"lng":129.0756,"radius":2000},
], "카페")

print("\n[교집합 없음 — 홍대 vs 강남 (반경 1km)]")
test("홍대vs강남_작은반경", [
    {"lat":37.5573,"lng":126.9245,"radius":1000},
    {"lat":37.4979,"lng":127.0276,"radius":1000},
], "카페")

print("\n[거의 같은 위치 (반경 500m)]")
test("같은위치", [
    {"lat":37.5573,"lng":126.9245,"radius":500},
    {"lat":37.5580,"lng":126.9250,"radius":500},
], "카페")

print("\n[자유 텍스트 — 우동]")
test("자유검색_우동", users_base, "우동")

print("\n[자유 텍스트 — 냉면]")
test("자유검색_냉면", users_base, "냉면")

print("\n[자유 텍스트 — 브런치]")
test("자유검색_브런치", users_base, "브런치")

print("\n[영어 카테고리 — cafe]")
test("영어_cafe", users_base, "cafe")

print("\n[영어 카테고리 — restaurant]")
test("영어_restaurant", users_base, "restaurant")

print(f"\n{'='*55}")
print("  테스트 완료")
print(f"{'='*55}\n")