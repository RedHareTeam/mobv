from concurrent.futures import ThreadPoolExecutor
import math

from recommend.place import search_places
from recommend.transit import get_transit_time
from recommend.intersection import get_intersection_shape, is_within_intersection, utm_to_latlon


def find_best_midpoint(users, radius_expansion=1.0, mode="transit"):
    """
    교집합 영역 내에서 대중교통 이동시간 최적 지하철역 선택 (2~5명)

    users = [
        {"lat": ..., "lng": ..., "radius": ...},
        ...
    ]

    반환:
    {
        "area_name": "홍대입구역",
        "center_lat": 37.5573,
        "center_lng": 126.9245,
        "users": [
            {"time": 30, "mode": "transit"},
            {"time": 27, "mode": "transit"},
            ...
        ],
        "total_time": 57
    }
    교집합이 없거나 교집합 내 역이 없으면 None 반환 → app.py 에서 교집합 centroid 사용.
    """
    shape = get_intersection_shape(users, radius_expansion)
    if shape is None:
        return None

    # 교집합 centroid 기준으로 역 탐색
    centroid = shape.centroid
    center_lat, center_lng = utm_to_latlon(centroid.x, centroid.y)

    # 교집합 유효반경 + 여유 500m 로 역 검색 (최소 2km)
    base_radius = int(math.sqrt(shape.area / math.pi))
    stations = search_places(
        "지하철역", center_lat, center_lng,
        radius=max(base_radius + 500, 2000), size=5,  # 10 → 5
    )

    # 교집합 내부에 있는 역만 후보로 사용
    candidates = [s for s in stations if is_within_intersection(s['lat'], s['lng'], shape)]
    if not candidates:
        return None

    def calc_score(station):
        times = [
            get_transit_time(u["lat"], u["lng"], station["lat"], station["lng"])
            for u in users
        ]
        if any(t is None for t in times):
            return None, float("inf")

        total = sum(times)
        max_t = max(times)
        min_t = min(times)
        score = total + (max_t - min_t) * 0.5  # 이동시간 불균형 패널티

        return {
            "area_name": station["name"],
            "center_lat": station["lat"],
            "center_lng": station["lng"],
            "users": [{"time": t, "mode": mode} for t in times],
            "total_time": total,
        }, score

    with ThreadPoolExecutor(max_workers=5) as executor:
        results = list(executor.map(calc_score, candidates))

    valid = [r for r in results if r[0] is not None]
    if not valid:
        return None

    best = min(valid, key=lambda x: x[1])
    return best[0]