import math

from recommend.place import search_places
from recommend.intersection import get_intersection_shape, is_within_intersection, utm_to_latlon


def find_best_midpoint(users, radius_expansion=1.0):
    """
    교집합 영역 내에서 가장 가까운 지하철역 선택.
    ODsay 대중교통 계산 없이 교집합 centroid 기준 거리만 사용.

    반환:
    {
        "area_name": "홍대입구역",
        "center_lat": 37.5573,
        "center_lng": 126.9245,
    }
    교집합이 없거나 교집합 내 역이 없으면 None 반환.
    """
    shape = get_intersection_shape(users, radius_expansion)
    if shape is None:
        return None

    # 교집합 centroid 기준으로 역 탐색
    centroid = shape.centroid
    center_lat, center_lng = utm_to_latlon(centroid.x, centroid.y)

    # 교집합 유효반경 + 여유 500m로 역 검색 (최소 2km)
    base_radius = int(math.sqrt(shape.area / math.pi))
    stations = search_places(
        "지하철역", center_lat, center_lng,
        radius=max(base_radius + 500, 2000), size=5,
    )

    # 교집합 내부에 있는 역만 후보로 사용
    candidates = [s for s in stations if is_within_intersection(s['lat'], s['lng'], shape)]
    if not candidates:
        return None

    # centroid와 가장 가까운 역 선택
    def dist_to_centroid(station):
        dlat = (station['lat'] - center_lat) * 111000
        dlng = (station['lng'] - center_lng) * 111000 * 0.82
        return dlat ** 2 + dlng ** 2

    best = min(candidates, key=dist_to_centroid)

    return {
        "area_name": best["name"],
        "center_lat": best["lat"],
        "center_lng": best["lng"],
    }