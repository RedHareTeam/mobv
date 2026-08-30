import os

from flask import Flask, request, jsonify
from flask_cors import CORS
from recommend.intersection import (
    calculate_intersection, get_intersection_shape, is_within_intersection, find_best_partial_intersection,
)
from recommend.place import search_places
from recommend.query_builder import build_search_queries, filter_by_category, search_with_multi_query
from recommend.weather import get_weather, get_weather_forecast
from recommend.midpoint import find_best_midpoint

app = Flask(__name__)
CORS(app)


# 잘못된 요청/서버 오류도 항상 JSON으로 응답 (Flutter 클라이언트가 항상 JSON을 기대하므로
# Werkzeug 기본 HTML 에러 페이지가 그대로 나가면 클라이언트단 JSON 파싱이 깨짐)
@app.errorhandler(400)
def bad_request(e):
    return jsonify({"error": "잘못된 요청입니다"}), 400


@app.errorhandler(404)
def not_found(e):
    return jsonify({"error": "존재하지 않는 경로입니다"}), 404


@app.errorhandler(415)
def unsupported_media_type(e):
    return jsonify({"error": "Content-Type은 application/json 이어야 합니다"}), 400


@app.errorhandler(500)
def server_error(e):
    # debug=True인 동안에는 이 핸들러 대신 Werkzeug 인터랙티브 디버거가 뜬다.
    # 배포 전 debug=False로 바꿔야 이 핸들러가 실제로 동작한다.
    print(f"서버 오류: {e}")
    return jsonify({"error": "서버에서 처리 중 오류가 발생했습니다"}), 500

# 영어→한글 카테고리 매핑
CATEGORY_MAP_EN = {
    "cafe": "카페",
    "restaurant": "맛집",
    "bar": "술집",
    "dessert": "디저트",
    "meat": "고기",
    "ramen": "라멘",
    "sushi": "초밥",
    "pizza": "피자",
    "pasta": "파스타",
    "malatang": "마라탕",
    "gukbap": "국밥",
    "korean": "한식",
    "cutlet": "돈까스",
    "izakaya": "이자카야",
    "study": "카공카페",
}


@app.route('/')
def index():
    return jsonify({"status": "Mobv API 서버 실행 중"})


def _search_and_filter(category, center_lat, center_lng, search_radius, shape, station_lat, station_lng):
    """장소 검색 + 필터링 + 정렬 공통 로직"""
    queries = build_search_queries(category)

    results = search_with_multi_query(
        search_places, queries,
        center_lat, center_lng,
        radius=search_radius,
        size_per_query=15
    )

    # 중복 제거
    seen = set()
    unique_places = []
    for p in results:
        if p['name'] not in seen:
            seen.add(p['name'])
            unique_places.append(p)

    # 카테고리 필터링
    filtered = filter_by_category(unique_places, category)
    top_places = filtered[:10]

    # 교집합 외부 장소 제거
    if shape:
        try:
            in_intersection = [p for p in top_places if is_within_intersection(p['lat'], p['lng'], shape)]
            if in_intersection:
                top_places = in_intersection
        except Exception as e:
            print(f"교집합 필터 오류: {e}")

    # 지하철역 근접도 기반 순위 재조정
    if station_lat is not None:
        def dist_to_station(p):
            dlat = (p['lat'] - station_lat) * 111000
            dlng = (p['lng'] - station_lng) * 111000 * 0.82
            return dlat ** 2 + dlng ** 2
        top_places.sort(key=dist_to_station)

    print(f"장소 수: {len(top_places)}, queries: {queries}, category: {category}")
    return top_places


def _validate_users(users):
    """
    users 배열 각 항목이 계산 가능한 값인지 검증.
    lat/lng/radius 중 하나라도 없거나 범위를 벗어나면 사람이 읽을 수 있는 오류 메시지 반환,
    이상 없으면 None 반환.
    검증 없이 calculate_intersection에 그대로 넘기면 KeyError/TypeError로 500이 나므로 여기서 막는다.
    """
    for i, u in enumerate(users):
        if not isinstance(u, dict):
            return f"{i+1}번째 사용자 데이터 형식이 올바르지 않습니다"
        for key in ("lat", "lng", "radius"):
            if key not in u:
                return f"{i+1}번째 사용자에 {key} 값이 없습니다"
            if not isinstance(u[key], (int, float)):
                return f"{i+1}번째 사용자의 {key} 값이 숫자가 아닙니다"
        if not (-90 <= u["lat"] <= 90):
            return f"{i+1}번째 사용자의 위도(lat) 값이 올바르지 않습니다"
        if not (-180 <= u["lng"] <= 180):
            return f"{i+1}번째 사용자의 경도(lng) 값이 올바르지 않습니다"
        # 프론트 원 그리기 최대 반경과 맞춰서 조정 필요 (우선 20km로 보수적 상한)
        if not (0 < u["radius"] <= 20000):
            return f"{i+1}번째 사용자의 radius 값이 올바르지 않습니다 (0~20000m)"
    return None


@app.route('/recommend', methods=['POST'])
def recommend():
    data = request.get_json(silent=True)

    if not data:
        return jsonify({"error": "데이터가 없습니다"}), 400

    users = data.get('users')
    category = data.get('category', '')

    # 구버전 호환: search_query → category 변환
    if not category:
        category = data.get('search_query', '맛집')

    if not users or not isinstance(users, list) or len(users) < 2:
        return jsonify({"error": "users 좌표가 2명 이상 필요합니다"}), 400

    if len(users) > 5:
        return jsonify({"error": "최대 5명까지 지원합니다"}), 400

    validation_error = _validate_users(users)
    if validation_error:
        return jsonify({"error": validation_error}), 400

    # radius_expansion 기본값
    radius_expansion = 1.0

    intersection = calculate_intersection(users, radius_expansion)
    center_lat = intersection["center_lat"]
    center_lng = intersection["center_lng"]
    search_radius = intersection["search_radius"]
    has_intersection = intersection["has_intersection"]

    # 교집합 없을 때 바로 안내
    if not has_intersection:
        try:
            partial = find_best_partial_intersection(users, radius_expansion)
        except Exception as e:
            print(f"부분 교집합 계산 오류: {e}")
            partial = None

        if partial:
            k, n = partial["matched_count"], partial["total_count"]
            missing = n - k
            # 정확한 비율(2/3, 4/5 등)은 메시지에 노출하지 않는다 — 숫자로 다수/소수를
            # 갈라 말하면, 누구를 지목하지 않아도 "편 가르기" 프레이밍 자체가 소외감을
            # 만들 수 있기 때문. 대신 얼마나 가까운 상황인지(1명만 남았는지, 그 이상인지)
            # 정도의 온도차만 전달한다. 원본 수치는 partialMatch에 그대로 들어있어
            # 필요하면 프론트에서 얼마든지 다르게(예: 본인에게만 조용히) 활용할 수 있다.
            if missing <= 1:
                message = "거의 다 만날 수 있는 지점이에요. 조금만 반경을 넓히면 될 것 같아요."
            else:
                message = "아직은 거리가 좀 있는 지점이에요. 반경을 조금 더 넓혀보시겠어요?"

            return jsonify({
                "hasIntersection": False,
                "message": message,
                "places": [],
                "partialMatch": partial,
            }), 200

        return jsonify({
            "hasIntersection": False,
            "message": "겹치는 지역이 없어요. 반경을 조금만 넓히면 새로운 추천 결과를 볼 수 있어요.",
            "places": []
        }), 200

    # 교집합 내 최적 지하철역 탐색
    try:
        midpoint = find_best_midpoint(users, radius_expansion)
    except Exception as e:
        print(f"midpoint 오류: {e}")
        midpoint = None

    area_name = midpoint["area_name"] if midpoint else None
    station_lat = midpoint["center_lat"] if midpoint else None
    station_lng = midpoint["center_lng"] if midpoint else None

    # 날씨 정보 (프론트 표시용)
    try:
        weather = get_weather(center_lat, center_lng)
    except Exception as e:
        print(f"날씨 오류: {e}")
        weather = {"condition": "clear", "temp": 0, "description": "알 수 없음"}

    # 리스트면 첫 번째 값만 사용
    if isinstance(category, list):
        category = category[0] if category else ''

    # 영어→한글 카테고리 변환
    category = CATEGORY_MAP_EN.get(category, category)

    # 교집합 shape 계산 (장소 필터링용)
    try:
        intersection_shape = get_intersection_shape(users, radius_expansion)
    except Exception as e:
        print(f"shape 계산 오류: {e}")
        intersection_shape = None

    # 장소 검색
    top_places = _search_and_filter(
        category,
        center_lat, center_lng,
        search_radius, intersection_shape,
        station_lat, station_lng
    )

    if len(top_places) < 2:
        return jsonify({"error": "추천 장소가 2곳 미만입니다. 원을 더 넓게 그려주세요."}), 422

    return jsonify({
        "hasIntersection": True,
        "area_name": area_name,
        "center_lat": center_lat,
        "center_lng": center_lng,
        "search_radius": search_radius,
        "weather": weather,
        "places": top_places
    })


@app.route('/weather/forecast', methods=['GET'])
def weather_forecast():
    date_str = request.args.get('date')
    if not date_str:
        return jsonify({"error": "date 파라미터가 필요합니다"}), 400

    lat = float(request.args.get('lat', 37.5665))
    lng = float(request.args.get('lng', 126.9780))

    forecast = get_weather_forecast(lat, lng, date_str)
    return jsonify(forecast)


if __name__ == '__main__':
    # 배포 환경에서는 FLASK_DEBUG를 설정하지 않으면 자동으로 False.
    # debug=True 상태로 배포하면 500 에러 시 Werkzeug 인터랙티브 디버거가 노출되어
    # 원격 코드 실행 위험이 있으므로 앱스토어 등록 전 반드시 확인할 것.
    debug_mode = os.getenv("FLASK_DEBUG", "false").lower() == "true"
    app.run(host="0.0.0.0", port=5000, debug=debug_mode)