import math

from recommend.place import search_places
from recommend.intersection import get_intersection_shape, utm_to_latlon


def find_best_midpoint(users, radius_expansion=1.0):
    """
    교집합 centroid에서 가장 가까운 지하철역 선택.
    ODsay 대중교통 계산 없이 단순 거리만 사용.

    주의: 역이 교집합 폴리곤 "안"에 있는지는 더 이상 체크하지 않는다. 렌즈 모양
    교집합은 양 끝이 뾰족해서, "폴리곤 안"이라는 조건만으로는 중심에서 1km 이상
    떨어진 뾰족한 끝 쪽 역이 뽑히는 반면, 중심에 훨씬 가까운 역이 경계 바로 밖에
    있다는 이유만으로 배제되는 문제가 있었다(실제로 재현해서 확인함). 역은 최종
    추천 장소가 아니라 "○○역 근처"라는 라벨과 정렬 기준으로만 쓰이므로(실제 장소
    후보는 별도로 교집합 안으로 필터링됨), 엄격한 폴리곤 포함 여부보다 "교집합 대표
    중심과 얼마나 가까운가"가 더 적합한 기준이다.

    역 주변 검색은 교집합 중심 검색을 보완할 뿐, 추천 허용 영역을 넓히지 않는다.
    최종 후보는 app.py에서 실제 교집합 내부인지 다시 확인한다.

    반환:
    {
        "area_name": "홍대입구역",
        "center_lat": 37.5573,
        "center_lng": 126.9245,
    }
    교집합이 없거나 주변에 역이 하나도 없으면 None 반환.
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
        radius=max(base_radius + 500, 2000), size=15, sort="distance",
    )

    if not stations:
        return None

    # centroid와 가장 가까운 역 선택
    def dist_to_centroid(station):
        dlat = (station['lat'] - center_lat) * 111000
        dlng = (station['lng'] - center_lng) * 111000 * 0.82
        return dlat ** 2 + dlng ** 2

    stations.sort(key=dist_to_centroid)
    nearby_stations = []
    seen_station_names = set()
    for station in stations:
        name = station["name"].strip()
        if not name or name in seen_station_names:
            continue
        seen_station_names.add(name)
        nearby_stations.append({
            "area_name": name,
            "center_lat": station["lat"],
            "center_lng": station["lng"],
        })
        if len(nearby_stations) == 3:
            break

    if not nearby_stations:
        return None

    return {
        **nearby_stations[0],
        "nearby_stations": nearby_stations,
    }