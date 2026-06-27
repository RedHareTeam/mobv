from recommend.query_builder import clean_search_query, get_primary_queries, filter_by_category
from recommend.place import search_places
from recommend.intersection import calculate_intersection
from kakao.kakao_parser import parse_kakao_txt
from nlp.rule_based import calculate_intimacy_score, get_intimacy_label, calculate_radius_expansion
from nlp.openai_analyzer import analyze_with_openai

# print("\n===== 카카오맵 장소 검색 테스트 =====")
# mood_list = ["감성"]
# base_query = clean_search_query("감성 한식당")
# primary_queries = get_primary_queries(mood_list, base_query)

# all_places = []
# for q in primary_queries:
#     results = search_places(q, 37.5572, 126.9249, radius=3000, size=5)
#     all_places.extend(results)

# # 중복 제거
# seen = set()
# unique_places = []
# for p in all_places:
#     if p['name'] not in seen:
#         seen.add(p['name'])
#         unique_places.append(p)

# # 카테고리 필터링
# filtered = filter_by_category(unique_places, base_query)

# print(f"Top5:")
# for p in filtered[:5]:
#     print(f"- {p['name']} | {p['category']} | {p['distance']}m")

# from recommend.place import search_places

# places = search_places("피자", 37.5572, 126.9249, radius=3000, size=5)
# print(f"\n피자 검색 ({len(places)}개):")
# for p in places:
#     print(f"- {p['name']} | {p['category']} | {p['distance']}m")

#===== OpenAI 취향 분석 테스트 =====
files = {
    "시나리오1 친구": "kakao/test_friend.txt",
    "시나리오2 지인": "kakao/test_acquaintance.txt",
    "시나리오3 직장": "kakao/test_work.txt"
}
for name, path in files.items():
    messages = parse_kakao_txt(path)
    result = analyze_with_openai(messages)
    print(f"\n========== {name} ==========")
    print(f"만남 목적: {result['purpose']}")
    print(f"선호 음식: {result['preferred_food']}")
    print(f"피하는 음식: {result['avoided_food']}")
    print(f"장소 유형: {result['place_type']}")
    print(f"분위기: {result['mood']}")
    print(f"검색 쿼리: {result['search_query']}")


#===== 친밀도 테스트 =====
for name, path in files.items():
    messages = parse_kakao_txt(path)
    score = calculate_intimacy_score(messages)
    label = get_intimacy_label(score)
    expansion = calculate_radius_expansion(score)
    print(f"\n========== {name} ==========")
    print(f"친밀도: {score}점 ({label})")
    print(f"반경 확장 배수: x{expansion}")


#===== 교집합 계산 테스트 =====
user1 = {"lat": 37.5573, "lng": 126.9245, "radius": 3000}
user2 = {"lat": 37.5443, "lng": 126.9526, "radius": 3000}
result = calculate_intersection(user1, user2, radius_expansion=1.0)
print(f"\n교집합 있는 경우:")
print(f"교집합 여부: {result['has_intersection']}")
print(f"중심 좌표: {result['center_lat']}, {result['center_lng']}")
print(f"검색 반경: {result['search_radius']}m")

user1 = {"lat": 37.5573, "lng": 126.9245, "radius": 1000}
user2 = {"lat": 37.4979, "lng": 127.0276, "radius": 1000}
result = calculate_intersection(user1, user2, radius_expansion=1.0)
print(f"\n교집합 없는 경우:")
print(f"교집합 여부: {result['has_intersection']}")
print(f"중심 좌표: {result['center_lat']}, {result['center_lng']}")
print(f"검색 반경: {result['search_radius']}m")

result = calculate_intersection(user1, user2, radius_expansion=1.5)
print(f"\n반경 확장 (x1.5) 경우:")
print(f"교집합 여부: {result['has_intersection']}")
print(f"중심 좌표: {result['center_lat']}, {result['center_lng']}")
print(f"검색 반경: {result['search_radius']}m")