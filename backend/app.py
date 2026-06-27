from flask import Flask, request, jsonify
from flask_cors import CORS
from recommend.intersection import calculate_intersection, get_intersection_shape, is_within_intersection
from recommend.place import search_places
from recommend.query_builder import build_search_queries, filter_by_category, search_with_multi_query
from recommend.weather import get_weather, get_weather_forecast
from recommend.midpoint import find_best_midpoint

app = Flask(__name__)
CORS(app)


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


@app.route('/recommend', methods=['POST'])
def recommend():
    data = request.get_json()

    if not data:
        return jsonify({"error": "데이터가 없습니다"}), 400

    users = data.get('users')
    category = data.get('category', '')

    if not users or len(users) < 2:
        return jsonify({"error": "users 좌표가 2명 이상 필요합니다"}), 400

    if len(users) > 5:
        return jsonify({"error": "최대 5명까지 지원합니다"}), 400

    # radius_expansion 기본값
    radius_expansion = 1.0

    intersection = calculate_intersection(users, radius_expansion)
    center_lat = intersection["center_lat"]
    center_lng = intersection["center_lng"]
    search_radius = intersection["search_radius"]
    has_intersection = intersection["has_intersection"]

    # 교집합 없을 때 바로 안내
    if not has_intersection:
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

    # place_type 처리
    if isinstance(category, list):
        category = category[0] if category else ''

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
    app.run(host="0.0.0.0", port=5000, debug=True)