from pyproj import Transformer
from shapely.geometry import Point
from itertools import combinations
import math

# 위도/경도 ↔ UTM 좌표계 변환기
# EPSG:4326 = 위도/경도, EPSG:32652 = UTM Zone 52N (한국)
transformer_to_utm = Transformer.from_crs("EPSG:4326", "EPSG:32652", always_xy=True)
transformer_to_latlon = Transformer.from_crs("EPSG:32652", "EPSG:4326", always_xy=True)

# 교집합이 "스치기만 하는" 수준(면적이 사실상 0에 가까운 경우)인지 판단하는 기준.
# 이보다 반경이 작으면 기하학적으로는 겹쳐도 실사용 가능한 교집합으로 치지 않는다.
# calculate_intersection과 find_best_partial_intersection 양쪽에서 동일하게 적용해야
# "전체 교집합에서는 걸러지는 허수 교집합이 부분 매칭에서는 통과하는" 불일치가 안 생긴다.
MIN_USABLE_RADIUS = 300


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
        return {
            "has_intersection": False,
            "center_lat": None,
            "center_lng": None,
            "search_radius": None
        }

    # 교집합 넓이가 있어도, 반경으로 환산했을 때 너무 작으면(원이 스치는 수준)
    # 실사용 가능한 교집합으로 보지 않는다 — 그대로 통과시키면 search_radius를
    # 500으로 강제로 띄워서 실제로는 거의 안 겹치는데 "500m 반경 정도는 겹친다"고
    # 잘못 보고하게 된다.
    raw_radius = int(math.sqrt(intersection.area / math.pi))
    if raw_radius < MIN_USABLE_RADIUS:
        return {
            "has_intersection": False,
            "center_lat": None,
            "center_lng": None,
            "search_radius": None
        }

    # 교집합 중심 좌표 추출
    center = intersection.centroid
    center_lat, center_lng = utm_to_latlon(center.x, center.y)

    # 주의: raw_radius가 MIN_USABLE_RADIUS(300)는 넘었지만 500 미만인 경우,
    # 여기서 500으로 올려 보고한다. "실제로 겹치는가"의 기준(300)과
    # "카카오 검색에 쓸 실용적 최소 반경"의 기준(500)은 서로 다른 목적의 값이라
    # 의도적으로 분리해뒀다 — 버그가 아니다. 즉 search_radius는 "진짜 교집합 크기"를
    # 그대로 보여주는 값이 아니라 "이 정도 반경으로 검색하겠다"는 값이라는 점에 주의.
    return {
        "has_intersection": True,
        "center_lat": round(center_lat, 6),
        "center_lng": round(center_lng, 6),
        "search_radius": max(raw_radius, 500)
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


def find_best_partial_intersection(users, radius_expansion=1.0):
    """
    전원 교집합이 없을 때, "가장 많은 인원이 겹치는 지점"을 찾는다.

    설계 의도: 누가 넓혀야 하는지 지목하지 않는다. "여기면 k/N명은 이미 겹쳐요"라는
    사실만 알려주고, 자기가 그 k명에 포함되는지는 각자 화면에서 자기 원과 이 지점을
    비교해서 스스로 확인하게 한다.

    방법: N-1명, N-2명, ... 2명까지 내려가며 모든 부분집합을 브루트포스로 검사한다
    (인원이 최대 5명이라 조합 수가 적어 전수 탐색으로 충분하다). 각 인원 수(k)에서
    MIN_USABLE_RADIUS 이상인(=원이 스치는 수준이 아니라 실제로 쓸 만한 교집합인)
    후보만 남기고, 그런 후보가 하나라도 있는 가장 큰 k를 택한다. 그 k 안에서
    후보가 여럿이면 교집합 면적이 가장 넓은(=가장 여유 있는) 조합을 고른다.

    이 임계값 체크가 핵심이다: 만약 없으면, k가 큰 조합이 "면적은 사실상 0인데
    기하학적으로는 겹침"이라는 이유만으로 선택되어, 인원 수는 더 적어도 훨씬 넉넉하게
    겹치는 조합이 검토조차 안 되는 문제가 생긴다. (예: 4/5명 조합이 반경 몇십m 수준의
    허수 교집합이면, 실제로는 3/5명이 반경 2km로 넉넉히 겹치는 조합이 훨씬 유용한데도
    k가 크다는 이유만으로 4/5명 쪽이 뽑혀버림.) 그래서 k가 큰 것을 무조건 우선하지
    않고, "그 k에서 실사용 가능한 후보가 있는지"를 먼저 확인한 뒤에만 그 k를 채택한다.

    1명짜리 부분집합(k=1)은 "교집합"이라 부를 수 없는 자명한 경우라 탐색 대상에서
    제외한다. 그래서 전체 인원이 2명일 때 이미 안 겹치면, 내려갈 더 작은 의미 있는
    부분집합이 없으므로 None을 반환한다 (설계 결함이 아니라 2명일 때는 원래 그런 것).

    반환: {
        "center_lat", "center_lng",   # 부분집합 교집합의 중심
        "matched_count",              # 이 지점에서 겹치는 인원 수 (k)
        "total_count",                # 전체 인원 수 (N)
        "search_radius",              # 그 교집합의 실제 검색 반경
    }
    또는 실사용 가능한 부분집합이 전혀 없으면 None
    (예: 서울 vs 부산처럼 아무 조합도 안 겹치거나, 겹쳐도 전부 스치는 수준일 때)
    """
    n = len(users)

    for k in range(n - 1, 1, -1):  # N-1명 → 2명까지
        best_at_k = None
        best_area_at_k = -1

        for combo in combinations(range(n), k):
            subset = [users[idx] for idx in combo]
            shape = get_intersection_shape(subset, radius_expansion)
            if shape is None:
                continue

            radius = int(math.sqrt(shape.area / math.pi))
            if radius < MIN_USABLE_RADIUS:
                # 스치는 수준(허수 교집합) — 이 k에서 겹친 걸로 치지 않는다
                continue

            if shape.area > best_area_at_k:
                center = shape.centroid
                center_lat, center_lng = utm_to_latlon(center.x, center.y)
                best_at_k = {
                    "center_lat": round(center_lat, 6),
                    "center_lng": round(center_lng, 6),
                    "matched_count": k,
                    "total_count": n,
                    "search_radius": max(radius, 500),
                }
                best_area_at_k = shape.area

        if best_at_k is not None:
            # 이 인원 수(k)에서 "실사용 가능한" 후보를 하나라도 찾았으면,
            # 인원이 더 적은 부분집합은 볼 필요가 없다 (항상 인원이 많은 쪽이 우선).
            # 허수 교집합만 있는 경우는 여기서 안 걸리고 계속 k를 내려간다.
            return best_at_k

    return None