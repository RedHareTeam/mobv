from pyproj import Transformer
from shapely.geometry import Point

# 위도/경도 ↔ UTM 좌표계 변환기
# EPSG:4326 = 위도/경도, EPSG:32652 = UTM Zone 52N (한국)
transformer_to_utm = Transformer.from_crs("EPSG:4326", "EPSG:32652", always_xy=True)
transformer_to_latlng = Transformer.from_crs("EPSG:32652", "EPSG:4326", always_xy=True)


def latlon_to_utm(lat, lng):
    """위도/경도 → UTM 좌표 변환"""
    x, y = transformer_to_utm.transform(lng, lat)
    return x, y


def utm_to_latlon(x, y):
    """UTM 좌표 → 위도/경도 변환"""
    lng, lat = transformer_to_latlon.transform(x, y)
    return lat, lng


def calculate_intersection(user1, user2, radius_expansion=1.0):
    """
    두 사용자의 이동 가능 구역 교집합 계산

    입력:
    user1 = {"lat": 37.5665, "lng": 126.9780, "radius": 3000}
    user2 = {"lat": 37.4979, "lng": 127.0276, "radius": 3000}
    radius_expansion = 친밀도 기반 반경 확장 배수

    반환:
    {
        "has_intersection": True/False,
        "center_lat": 37.5320,
        "center_lng": 127.0028,
        "search_radius": 3000
    }
    """
    # 위도/경도 → UTM 변환
    x1, y1 = latlon_to_utm(user1['lat'], user1['lng'])
    x2, y2 = latlon_to_utm(user2['lat'], user2['lng'])

    # 반경 확장 적용
    r1 = user1['radius'] * radius_expansion
    r2 = user2['radius'] * radius_expansion

    # Shapely 원 생성
    circle1 = Point(x1, y1).buffer(r1)
    circle2 = Point(x2, y2).buffer(r2)

    # 교집합 계산
    intersection = circle1.intersection(circle2)

    if intersection.is_empty:
        # 교집합 없음 → 중간지점 반환
        mid_x = (x1 + x2) / 2
        mid_y = (y1 + y2) / 2
        mid_lat, mid_lng = utm_to_latlon(mid_x, mid_y)

        return {
            "has_intersection": False,
            "center_lat": round(mid_lat, 6),
            "center_lng": round(mid_lng, 6),
            "search_radius": int((r1 + r2) / 2)
        }

    # 교집합 중심 좌표 추출
    center = intersection.centroid
    center_lat, center_lng = utm_to_latlon(center.x, center.y)

    # 검색 반경 = 교집합 넓이 기반
    import math
    search_radius = int(math.sqrt(intersection.area / math.pi))

    return {
        "has_intersection": True,
        "center_lat": round(center_lat, 6),
        "center_lng": round(center_lng, 6),
        "search_radius": max(search_radius, 500)  # 최소 500m
    }