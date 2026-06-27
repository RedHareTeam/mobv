import requests

url = "http://localhost:5000/recommend"

users = [
    {"lat": 37.5573, "lng": 126.9245, "radius": 3000},
    {"lat": 37.5443, "lng": 126.9526, "radius": 3000},
]

categories = ["카페", "맛집", "술집", "디저트", "라멘", "파스타", "피자", "초밥", "고기", "국밥", "마라탕"]

for category in categories:
    data = {"users": users, "category": category}
    response = requests.post(url, json=data)
    result = response.json()

    if not result.get('hasIntersection'):
        print(f"[{category}] 교집합 없음")
        continue

    places = result.get('places', [])
    print(f"[{category}] {len(places)}개")
    for p in places[:3]:
        print(f"  - {p['name']} | {p['category']}")
    print()