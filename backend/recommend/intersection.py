from pyproj import Transformer
from shapely.geometry import Point
import math

# 위도/경도 ↔ UTM 좌표계 변환기
# EPSG:4326 = 위도/경도, EPSG:32652 = UTM Zone 52N (한국)
transformer_to_utm = Transformer.from_crs("EPSG:4326", "EPSG:32652", always_xy=True)
transformer_to_latlon = Transformer.from_crs("EPSG:32652", "EPSG:4326", always_xy=True)


def latlon_to_utm(lat, lng):
    """위도/경도 → UTM 좌표 변환"""
    x, y = transformer_to_utm.transform(lng, lat)
    return x, y


def utm_to_latlon(x, y):
    """UTM 좌표 → 위도/경도 변환"""
    lng, lat = transformer_to_latlon.transform(x, y)
    return lat, lng


def calculate_intersection(users, radius_expansion=1.0):
    """
    다수 사용자의 이동 가능 구역 교집합 계산 (2~5명)

    입력:
    users = [
        {"lat": 37.5665, "lng": 126.9780, "radius": 3000},
        {"lat": 37.4979, "lng": 127.0276, "radius": 3000},
        ...
    ]
    radius_expansion = 친밀도 기반 반경 확장 배수

    반환:
    {
        "has_intersection": True/False,
        "center_lat": 37.5320,
        "center_lng": 127.0028,
        "search_radius": 1500
    }
    """
    if not users:
        return None

    # 원 생성
    circles = []
    for user in users:
        x, y = latlon_to_utm(user['lat'], user['lng'])
        r = user['radius'] * radius_expansion
        circles.append(Point(x, y).buffer(r))

    # 전체 교집합 계산
    intersection = circles[0]
    for circle in circles[1:]:
        intersection = intersection.intersection(circle)

    if intersection.is_empty:
        # 교집합 없음 → 전체 중간지점 반환
        xs = [latlon_to_utm(u['lat'], u['lng'])[0] for u in users]
        ys = [latlon_to_utm(u['lat'], u['lng'])[1] for u in users]
        mid_lat, mid_lng = utm_to_latlon(sum(xs) / len(xs), sum(ys) / len(ys))

        return {
            "has_intersection": False,
            "center_lat": round(mid_lat, 6),
            "center_lng": round(mid_lng, 6),
            "search_radius": 1500
        }

    # 교집합 중심 좌표 추출
    center = intersection.centroid
    center_lat, center_lng = utm_to_latlon(center.x, center.y)

    # 검색 반경 = 교집합 넓이 기반
    search_radius = int(math.sqrt(intersection.area / math.pi))

    return {
        "has_intersection": True,
        "center_lat": round(center_lat, 6),
        "center_lng": round(center_lng, 6),
        "search_radius": max(search_radius, 500)
    }


def get_intersection_shape(users, radius_expansion=1.0):
    """교집합 Shapely geometry 반환 (교집합 없으면 None)"""
    circles = []
    for user in users:
        x, y = latlon_to_utm(user['lat'], user['lng'])
        r = user['radius'] * radius_expansion
        circles.append(Point(x, y).buffer(r))

    shape = circles[0]
    for circle in circles[1:]:
        shape = shape.intersection(circle)

    return None if shape.is_empty else shape


def is_within_intersection(lat, lng, shape):
    """좌표가 교집합 내부에 있는지 확인"""
    x, y = latlon_to_utm(lat, lng)
    return shape.contains(Point(x, y))