from flask import Flask, request, jsonify
from flask_cors import CORS
from kakao.kakao_parser import parse_kakao_txt
from nlp.openai_analyzer import analyze_with_openai
from nlp.rule_based import calculate_intimacy_score, get_intimacy_label, calculate_radius_expansion
import os
import tempfile
from recommend.intersection import calculate_intersection, get_intersection_shape, is_within_intersection
from recommend.place import search_places
from recommend.query_builder import build_search_queries, filter_by_category, search_with_multi_query
from recommend.weather import get_weather, get_weather_forecast
from recommend.midpoint import find_best_midpoint

app = Flask(__name__)
CORS(app)

QUERY_TO_PLACE_TYPE = {
    "카페": "카페", "노트북 카페": "카페", "술집 맛집": "술집",
    "맛집": "한식당", "한식당": "한식당", "파스타집": "파스타집",
    "라멘집": "라멘집", "피자집": "피자집", "술집": "술집",
    "이자카야": "이자카야", "바": "바", "스터디카페": "스터디카페",
    "감성 카페": "카페", "감성 한식당": "한식당", "감성 파스타집": "파스타집",
    "감성 라멘집": "라멘집", "감성 피자집": "피자집",
}

@app.route('/')
def index():
    return jsonify({"status": "Chemeet API 서버 실행 중"})


@app.route('/analyze', methods=['POST'])
def analyze():
    tmp_path = None

    try:
        if not request.is_json:
            return jsonify({"error": "JSON 형식으로 요청해주세요"}), 400

        data = request.get_json()
        txt_content = data.get('txt_content', '')
        if not txt_content:
            return jsonify({"error": "txt_content가 비어있습니다"}), 400

        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w', encoding='utf-8') as tmp:
            tmp.write(txt_content)
            tmp_path = tmp.name

        messages = parse_kakao_txt(tmp_path)

        if not messages:
            return jsonify({"error": "파싱된 메시지가 없습니다"}), 400

        keywords = analyze_with_openai(messages)

        INTIMACY_MAX_MESSAGES = 100
        messages_for_intimacy = messages[-INTIMACY_MAX_MESSAGES:]
        intimacy_score = calculate_intimacy_score(messages_for_intimacy)
        intimacy_label = get_intimacy_label(intimacy_score)
        radius_expansion = calculate_radius_expansion(intimacy_score)

        senders = keywords['senders']

        # search_query 생성 
        place_type_list = keywords.get('place_type', [])
        main_place = place_type_list[0] if place_type_list else '맛집'
        search_query = keywords.get('search_query', main_place)

        return jsonify({
            "senders": senders,
            "partner_name": senders[1] if len(senders) >= 2 else "",
            "intimacy_score": intimacy_score,
            "intimacy_label": intimacy_label,
            "radius_expansion": radius_expansion,
            "purpose": keywords['purpose'],
            "preferred_food": keywords['preferred_food'],
            "avoided_food": keywords['avoided_food'],
            "place_type": keywords['place_type'],
            "secondary_place_type": keywords['secondary_place_type'],
            "mood": keywords['mood'],
            "search_query": search_query,
            "keywords": keywords['mood'] + keywords['place_type'],
        })

    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.remove(tmp_path)


def _search_and_filter(place_type, mood, preferred_food, center_lat, center_lng, search_radius, users, radius_expansion, station_lat, station_lng, purpose=None):
    queries = build_search_queries(place_type, mood, preferred_food, purpose)

    results = search_with_multi_query(
        search_places, queries,
        center_lat, center_lng,
        radius=search_radius,
        size_per_query=10
    )

    seen = set()
    unique_places = []
    for p in results:
        if p['name'] not in seen:
            seen.add(p['name'])
            unique_places.append(p)

    filtered = filter_by_category(unique_places, place_type)
    top_places = filtered[:20]

    try:
        shape = get_intersection_shape(users, radius_expansion)
        if shape:
            in_intersection = [p for p in top_places if is_within_intersection(p['lat'], p['lng'], shape)]
            if in_intersection:
                top_places = in_intersection
    except Exception as e:
        print(f"교집합 필터 오류: {e}")

    if station_lat is not None:
        def dist_to_station(p):
            dlat = (p['lat'] - station_lat) * 111000
            dlng = (p['lng'] - station_lng) * 111000 * 0.82
            return dlat ** 2 + dlng ** 2
        top_places.sort(key=dist_to_station)

    print(f"장소 수: {len(top_places)}, queries: {queries}, place_type: {place_type}")
    return top_places


@app.route('/recommend', methods=['POST'])
def recommend():
    data = request.get_json()

    if not data:
        return jsonify({"error": "데이터가 없습니다"}), 400

    users = data.get('users')
    mood = data.get('mood', [])
    intimacy_score = data.get('intimacy_score', 50)
    preferred_food = data.get('preferred_food', [])
    purpose = data.get('purpose', '친목')

    search_query = data.get('search_query', '')
    place_type_raw = data.get('place_type') or QUERY_TO_PLACE_TYPE.get(search_query, '')

    if not users or len(users) < 2:
        return jsonify({"error": "users 좌표가 2명 이상 필요합니다"}), 400

    if len(users) > 5:
        return jsonify({"error": "최대 5명까지 지원합니다"}), 400

    radius_expansion = calculate_radius_expansion(intimacy_score)

    intersection = calculate_intersection(users, radius_expansion)
    center_lat   = intersection["center_lat"]
    center_lng   = intersection["center_lng"]
    search_radius = intersection["search_radius"]

    try:
        midpoint = find_best_midpoint(users, radius_expansion)
    except Exception as e:
        print(f"midpoint 오류: {e}")
        midpoint = None

    area_name   = midpoint["area_name"]  if midpoint else None
    station_lat = midpoint["center_lat"] if midpoint else None
    station_lng = midpoint["center_lng"] if midpoint else None

    try:
        weather = get_weather(center_lat, center_lng)
    except Exception as e:
        print(f"날씨 오류: {e}")
        weather = {"condition": "clear", "temp": 0, "description": "알 수 없음"}
    condition = weather.get("condition", "clear")

    if condition in ["rain", "snow", "thunder"]:
        search_radius = min(search_radius, 1500)
        stations = search_places("지하철역", center_lat, center_lng, radius=2000, size=3)
        if stations:
            nearest    = stations[0]
            center_lat = nearest['lat']
            center_lng = nearest['lng']
            area_name  = nearest['name']

    if isinstance(place_type_raw, list):
        place_type = place_type_raw[0] if place_type_raw else ''
    else:
        place_type = place_type_raw or ''

    secondary_place_type = data.get('secondary_place_type', '')
    if isinstance(secondary_place_type, list):
        secondary_place_type = secondary_place_type[0] if secondary_place_type else ''

    top_places = _search_and_filter(
        place_type, mood, preferred_food,
        center_lat, center_lng,
        search_radius, users, radius_expansion, station_lat, station_lng,
        purpose=purpose
    )

    if len(top_places) < 2:
        return jsonify({"error": "추천 장소가 2곳 미만입니다. 원을 더 넓게 그려주세요."}), 422

    secondary_places = []
    if secondary_place_type:
        dessert_foods = [f for f in preferred_food if any(k in f for k in ["디저트", "케이크", "마카롱", "타르트", "와플", "빵", "크루아상", "스콘"])]
        secondary_places = _search_and_filter(
            secondary_place_type, mood, dessert_foods,
            center_lat, center_lng,
            search_radius, users, radius_expansion, station_lat, station_lng
        )

    response = {
        "has_intersection": intersection["has_intersection"],
        "area_name": area_name,
        "center_lat": center_lat,
        "center_lng": center_lng,
        "search_radius": search_radius,
        "weather": weather,
        "users_transit": midpoint["users"] if midpoint else None,
        "total_time": midpoint["total_time"] if midpoint else None,
        "places": top_places
    }

    if secondary_places:
        response["secondary_places"] = secondary_places

    return jsonify(response)


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