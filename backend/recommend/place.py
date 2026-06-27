import requests
import os
from dotenv import load_dotenv

load_dotenv()

KAKAO_API_KEY = os.getenv("KAKAO_REST_KEY")
KAKAO_LOCAL_URL = "https://dapi.kakao.com/v2/local/search/keyword.json"


def search_places(query, lat, lng, radius=1500, size=5):
    """
    카카오맵 로컬 API로 장소 검색

    입력:
    - query: 검색 키워드 (예: "감성 카페")
    - lat, lng: 중심 좌표
    - radius: 검색 반경 (미터)
    - size: 결과 개수 (최대 15)

    반환:
    [
        {
            "name": "장소명",
            "address": "주소",
            "category": "카테고리",
            "lat": 37.5320,
            "lng": 127.0028,
            "url": "카카오맵 링크"
        }
    ]
    """
    headers = {"Authorization": f"KakaoAK {KAKAO_API_KEY}"}
    params = {
        "query": query,
        "x": lng,
        "y": lat,
        "radius": radius,
        "size": size,
        "sort": "accuracy"
    }

    response = requests.get(KAKAO_LOCAL_URL, headers=headers, params=params)

    if response.status_code != 200:
        return []

    data = response.json()
    places = []

    for item in data.get("documents", []):
        places.append({
            "name": item["place_name"],
            "address": item["road_address_name"] or item["address_name"],
            "category": item["category_name"],
            "lat": float(item["y"]),
            "lng": float(item["x"]),
            "url": item["place_url"],
            "distance": int(item["distance"]) if item["distance"] else 0,
            "kakaoId": item["id"]  # 추가
        })

    return places