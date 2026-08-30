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
        # 카카오 로컬 API가 허용하는 radius 상한은 20000m. 이 함수의 호출자 대부분은
        # (app.py의 search_radius) 사용자 입력 검증(≤20000) 덕에 이 값을 넘지 않지만,
        # midpoint.py는 base_radius + 500을 그대로 넘겨서 base_radius가 20000에
        # 가까우면 이 상한을 실제로 넘을 수 있다. 호출자마다 따로 막기보다 여기서
        # 한 번에 클램프하는 게 안전하다 — 안 그러면 카카오가 400을 반환하고
        # place.py는 그걸 "결과 없음"으로 조용히 삼켜서 나중에 원인 찾기 어려워진다.
        "radius": min(radius, 20000),
        "size": size,
        "sort": "accuracy"
    }

    try:
        response = requests.get(KAKAO_LOCAL_URL, headers=headers, params=params, timeout=5)
    except requests.exceptions.RequestException as e:
        # 카카오 API 타임아웃/네트워크 오류 시 요청 전체를 막지 않고 빈 결과로 degrade
        # (weather.py의 실패 처리 방식과 동일)
        print(f"카카오 API 요청 오류: {e}")
        return []

    if response.status_code != 200:
        return []

    try:
        data = response.json()
    except ValueError as e:
        print(f"카카오 API 응답 파싱 오류: {e}")
        return []

    places = []

    for item in data.get("documents", []):
        try:
            places.append({
                "name": item.get("place_name", ""),
                "address": item.get("road_address_name") or item.get("address_name", ""),
                "category": item.get("category_name", ""),
                # 좌표는 .get()으로 기본값을 채우지 않는다 — lat/lng이 0,0으로 채워지면
                # "서울 앞바다"라는 유효해 보이지만 완전히 틀린 위치가 조용히 섞여 들어간다.
                # 좌표가 진짜 없으면 이 장소 자체를 건너뛰는 게 맞다 (아래 except에서 처리).
                "lat": float(item["y"]),
                "lng": float(item["x"]),
                "url": item.get("place_url", ""),
                "distance": int(item.get("distance") or 0),
                "kakaoId": item.get("id", "")
            })
        except (KeyError, ValueError, TypeError) as e:
            # 카카오가 특정 문서에서 필드를 하나 빼먹어도, 그 장소 하나만 건너뛰고
            # 나머지 결과는 살린다. 이게 없으면 문서 하나 이상하다고 /recommend
            # 요청 전체가(특히 단일 쿼리 카테고리는 search_with_multi_query에서
            # try/except로 안 감싸여 있어서) 그대로 실패한다.
            print(f"장소 파싱 오류(건너뜀): {e}, place_name={item.get('place_name', '?')}")
            continue

    return places