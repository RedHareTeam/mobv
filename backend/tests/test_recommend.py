import requests
from recommend.weather import get_weather

url = "http://172.20.10.3:5000/recommend"

data = {
    "user1": {"lat": 37.5573, "lng": 126.9245, "radius": 3000},
    "user2": {"lat": 37.5443, "lng": 126.9526, "radius": 3000},
    "search_query": "감성 피자집",
    "mood": ["감성"],
    "intimacy_score": 77.5
}

response = requests.post(url, json=data)
result = response.json()

print(f"교집합 여부: {result['has_intersection']}")
print(f"중심 좌표: {result['center_lat']}, {result['center_lng']}")
print(f"검색 반경: {result['search_radius']}m")
print(f"날씨: {result.get('weather', {}).get('description', '없음')} ({result.get('weather', {}).get('condition', '')})")
print(f"기온: {result.get('weather', {}).get('temp', '')}°C")
print(f"\n추천 장소:")
for p in result['places']:
    print(f"- {p['name']} | {p['category']} | {p['distance']}m")