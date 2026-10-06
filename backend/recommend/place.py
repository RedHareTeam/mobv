import requests
import os
from dotenv import load_dotenv

load_dotenv()

KAKAO_API_KEY = os.getenv("KAKAO_REST_KEY")
KAKAO_LOCAL_URL = "https://dapi.kakao.com/v2/local/search/keyword.json"


class PlaceSearchError(RuntimeError):
    """카카오 장소 검색이 정상적인 무결과가 아닌 이유로 실패한 경우."""


def _normalize_place(item):
    """카카오 문서 한 건을 앱과 백엔드가 공유하는 장소 응답 형식으로 변환한다."""
    name = str(item.get("place_name") or "").strip()
    kakao_id = str(item.get("id") or "").strip()
    if not name or not kakao_id:
        return None

    try:
        lat = float(item["y"])
        lng = float(item["x"])
        if not (-90 <= lat <= 90 and -180 <= lng <= 180):
            return None
    except (KeyError, TypeError, ValueError):
        return None

    try:
        distance = int(item.get("distance") or 0)
    except (TypeError, ValueError):
        distance = 0

    return {
        "name": name,
        "address": str(item.get("road_address_name") or item.get("address_name") or ""),
        "category": str(item.get("category_name") or ""),
        "lat": lat,
        "lng": lng,
        "url": str(item.get("place_url") or ""),
        "distance": max(distance, 0),
        "kakaoId": kakao_id,
    }


def search_places(query, lat, lng, radius=1500, size=5, sort="accuracy"):
    """
    카카오맵 로컬 API로 장소 검색

    입력:
    - query: 검색 키워드 (예: "감성 카페")
    - lat, lng: 중심 좌표
    - radius: 검색 반경 (미터)
    - size: 결과 개수 (최대 15)

    반환: 모든 레코드가 아래 정규화된 형식을 따르는 장소 리스트.
    [
        {
            "name": "장소명",
            "address": "주소",
            "category": "카테고리",
            "lat": 37.5320,
            "lng": 127.0028,
            "url": "카카오맵 링크",
            "distance": 100,
            "kakaoId": "카카오 장소 ID"
        }
    ]
    """
    headers = {"Authorization": f"KakaoAK {KAKAO_API_KEY}"}
    params = {
        "query": query,
        "x": lng,
        "y": lat,
        # 카카오 로컬 API가 허용하는 radius 상한은 20000m. 이 함수의 호출자 대부분은
        # (app.py의 search_radius) 사용자 입력 검증(≤20000) 덕에 이 값을 넘지 않지만,
        # midpoint.py는 base_radius + 500을 그대로 넘겨서 base_radius가 20000에
        # 가까우면 이 상한을 실제로 넘을 수 있다. 호출자마다 따로 막기보다 여기서
        # 한 번에 클램프하는 게 안전하다 — 400 응답은 정상적인 무결과와 구분해
        # PlaceSearchError로 호출자에게 전달한다.
        "radius": min(radius, 20000),
        "size": size,
        "sort": sort
    }

    try:
        response = requests.get(KAKAO_LOCAL_URL, headers=headers, params=params, timeout=5)
    except requests.exceptions.RequestException as e:
        raise PlaceSearchError("Kakao Local API request failed") from e

    if response.status_code != 200:
        raise PlaceSearchError(
            f"Kakao Local API returned HTTP {response.status_code}"
        )

    try:
        data = response.json()
    except ValueError as e:
        raise PlaceSearchError("Kakao Local API returned invalid JSON") from e

    if not isinstance(data, dict) or not isinstance(data.get("documents"), list):
        raise PlaceSearchError("Kakao Local API returned an invalid document list")

    documents = data["documents"]
    places = []
    invalid_count = 0
    for item in documents:
        if not isinstance(item, dict):
            invalid_count += 1
            continue
        normalized = _normalize_place(item)
        if normalized is None:
            invalid_count += 1
            continue
        places.append(normalized)

    if documents and invalid_count == len(documents):
        raise PlaceSearchError("Kakao Local API returned no valid place documents")
    if invalid_count:
        print(f"카카오 장소 응답에서 유효하지 않은 문서 {invalid_count}건을 제외했습니다")
    return places