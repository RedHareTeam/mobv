"""
Mobv 백엔드 회귀 테스트

목적:
1. category 매핑 버그(중식/일식 dead mapping, study 누락)가 다시 생기지 않는지 고정
2. /recommend 실패 케이스(입력 검증, 교집합 없음, 결과 부족)가 의도대로 동작하는지 확인
3. 조건에 맞지 않는 장소가 추천 결과에 포함되지 않는지 확인

실행: python3 -m pytest test_recommend.py -v
네트워크 호출(Kakao API, OpenWeather)은 전부 모킹되어 있어 API 키 없이 실행 가능합니다.
"""
import sys
import os
import requests
import pytest
from unittest.mock import patch, Mock
from shapely.geometry import Point

sys.path.insert(0, os.path.dirname(__file__))

import app as app_module
from recommend.query_builder import (
    CATEGORY_QUERY,
    CATEGORY_RULES,
    build_search_queries,
    filter_by_category,
    search_with_multi_query,
)
from recommend.intersection import calculate_intersection, find_best_partial_intersection, get_intersection_shape, utm_to_latlon
from recommend.place import PlaceSearchError, search_places
from recommend.weather import get_weather, get_weather_forecast
from recommend.midpoint import find_best_midpoint


# ── 픽스처 ──────────────────────────────────────────────

def make_client():
    app_module.app.config["TESTING"] = True
    return app_module.app.test_client()


def fake_place(name, lat, lng, category="음식점 > 카페", distance=100):
    return {
        "name": name, "address": "서울 어딘가", "category": category,
        "lat": lat, "lng": lng, "url": "https://place.kakao.com/x",
        "distance": distance, "kakaoId": name,
    }


SEOUL_USERS_OVERLAP = [
    {"lat": 37.5665, "lng": 126.9780, "radius": 3000},
    {"lat": 37.5675, "lng": 126.9790, "radius": 3000},
]

SEOUL_USERS_NO_OVERLAP = [
    {"lat": 37.5665, "lng": 126.9780, "radius": 300},
    {"lat": 37.4979, "lng": 127.0276, "radius": 300},  # 강남, 수 km 떨어짐
]


# ── 1. 카테고리 매핑 회귀 테스트 ──────────────────────────

class TestCategoryMapping:
    def test_no_dead_catchall_mappings(self):
        """16개 세분화 카테고리에 없는 catch-all(중식/일식)이 다시 추가되지 않았는지 확인"""
        assert "chinese" not in app_module.CATEGORY_MAP_EN
        assert "japanese" not in app_module.CATEGORY_MAP_EN

    def test_study_mapped_and_queryable(self):
        """study(프론트 실제 선택지) 매핑이 존재하고 실제 검색 쿼리를 만들 수 있는지 확인.
        '스터디카페'(공간대여업)가 아니라 '카공카페'(노트북 들고 여럿이 모여 작업/공부하는
        일반 카페)로 매핑되어야 한다 — 이 앱은 2~5명이 같이 모이는 용도라 개인 열람실형
        공간대여업과는 목적이 다르다."""
        assert app_module.CATEGORY_MAP_EN.get("study") == "카공카페"
        queries = build_search_queries(app_module.CATEGORY_MAP_EN["study"])
        assert queries and all(isinstance(q, str) for q in queries)

    def test_all_frontend_categories_resolve(self):
        """create_appointment_screen.dart의 실제 선택지 4개가 전부 유효한 카카오 쿼리로 이어지는지 확인"""
        frontend_values = ["cafe", "restaurant", "bar", "study"]
        for v in frontend_values:
            kr = app_module.CATEGORY_MAP_EN.get(v)
            assert kr is not None, f"{v} 매핑 누락"
            queries = build_search_queries(kr)
            assert len(queries) >= 1

    def test_every_category_query_key_has_a_filter_rule(self):
        """CATEGORY_QUERY에 있는 키는 전부 CATEGORY_RULES에도 있어야 한다 (필터링 누락 방지)"""
        missing = set(CATEGORY_QUERY) - set(CATEGORY_RULES)
        assert not missing, f"필터 규칙 없는 카테고리: {missing}"


# ── 2. 카테고리 필터링 테스트 ───────────────────────────

class TestCategoryFiltering:
    def test_empty_filter_result_stays_empty(self):
        places = [fake_place("아무거나", 37.56, 126.97, category="여행 > 관광명소")]
        result = filter_by_category(places, "카페")
        assert result == []

    def test_multi_query_provider_failure_is_not_hidden_by_other_results(self):
        def search_fn(query, lat, lng, radius, size):
            if query == "first":
                raise PlaceSearchError("provider unavailable")
            return [fake_place("부분 결과", lat, lng)]

        with pytest.raises(PlaceSearchError):
            search_with_multi_query(
                search_fn, ["first", "second"], 37.56, 126.97, 1000,
            )

    def test_pizza_blacklist_removes_franchise(self):
        places = [
            fake_place("도미노피자 강남점", 37.56, 126.97, category="음식점 > 피자"),
            fake_place("동네피자집", 37.56, 126.97, category="음식점 > 피자"),
        ]
        result = filter_by_category(places, "피자")
        names = [p["name"] for p in result]
        assert "도미노피자 강남점" not in names
        assert "동네피자집" in names

    def test_blacklist_all_franchise_stays_empty(self):
        """블랙리스트 장소만 검색되면 이를 추천 결과에 포함하지 않는다."""
        places = [fake_place("피자헛 역삼점", 37.56, 126.97, category="음식점 > 피자")]
        result = filter_by_category(places, "피자")
        assert result == []

    def test_study_filter_treats_it_as_cafe_subtype(self):
        """'카공카페'(노트북/작업 목적)는 '스터디카페'(개인 열람실형 공간대여업)와
        다른 개념으로 재정의했다 — 디저트와 동일하게 일반 카페의 하위 개념으로 취급하므로,
        일반 카페는 필터를 통과해야 하고(카페 자체가 목적이니까), 공간대여업 성격의
        장소는 필터 대상이 아니다(애초에 그런 검색어로 안 감)."""
        places = [
            fake_place("작업하기좋은카페", 37.56, 126.97, category="음식점 > 카페"),
            fake_place("관광안내소", 37.56, 126.97, category="여행 > 관광안내소"),
        ]
        result = filter_by_category(places, "카공카페")
        names = [p["name"] for p in result]
        assert "작업하기좋은카페" in names
        assert "관광안내소" not in names

    def test_study_blacklist_excludes_cheap_franchise(self):
        """카공카페도 디저트/카페와 동일하게 저가 프랜차이즈 블랙리스트가 적용되어야 한다
        (좌석 회전이 빨라 여럿이 앉아 작업하기엔 안 맞는 곳들)."""
        places = [
            fake_place("메가커피 강남점", 37.56, 126.97, category="음식점 > 카페"),
            fake_place("동네카페", 37.56, 126.97, category="음식점 > 카페"),
        ]
        result = filter_by_category(places, "카공카페")
        names = [p["name"] for p in result]
        assert "메가커피 강남점" not in names
        assert "동네카페" in names

    def test_study_blacklist_excludes_exact_unsuitable_place_name(self):
        places = [
            fake_place("적당", 37.56, 126.97, category="음식점 > 카페"),
            fake_place(" 적당 ", 37.56, 126.97, category="음식점 > 카페"),
            fake_place("적당커피", 37.56, 126.97, category="음식점 > 카페"),
        ]

        result = filter_by_category(places, "카공카페")

        assert [place["name"] for place in result] == ["적당커피"]

    def test_unsuitable_study_place_remains_available_in_regular_cafe_category(self):
        places = [fake_place("적당", 37.56, 126.97, category="음식점 > 카페")]

        assert filter_by_category(places, "카페") == places


# ── 3. place.py 네트워크 장애 대응 테스트 ─────────────────

class TestPlaceNetworkFailure:
    @patch("recommend.place.requests.get", side_effect=requests.exceptions.Timeout)
    def test_kakao_timeout_is_not_misreported_as_no_results(self, mock_get):
        with pytest.raises(PlaceSearchError):
            search_places("카페", 37.5665, 126.978)

    @patch("recommend.place.requests.get", side_effect=requests.exceptions.ConnectionError)
    def test_kakao_connection_error_is_reported(self, mock_get):
        with pytest.raises(PlaceSearchError):
            search_places("카페", 37.5665, 126.978)

    @patch("recommend.place.requests.get")
    def test_kakao_malformed_json_is_reported(self, mock_get):
        fake_response = Mock()
        fake_response.status_code = 200
        fake_response.json.side_effect = ValueError("bad json")
        mock_get.return_value = fake_response
        with pytest.raises(PlaceSearchError):
            search_places("카페", 37.5665, 126.978)

    @patch("recommend.place.requests.get")
    def test_kakao_non_200_is_reported(self, mock_get):
        fake_response = Mock()
        fake_response.status_code = 500
        mock_get.return_value = fake_response
        with pytest.raises(PlaceSearchError):
            search_places("카페", 37.5665, 126.978)

    @patch("recommend.place.requests.get")
    def test_document_missing_optional_field_survives_with_default(self, mock_get):
        """부가 필드가 없는 문서도 정규화된 형식과 기본값으로 살아남아야 한다."""
        fake_response = Mock()
        fake_response.status_code = 200
        fake_response.json.return_value = {
            "documents": [
                {
                    "place_name": "정상카페", "road_address_name": "",
                    "address_name": "서울시", "category_name": "카페",
                    "y": "37.5", "x": "127.0", "place_url": "url",
                    "distance": "100", "id": "1",
                },
                {
                    # road_address_name, distance 필드 자체가 없음
                    "place_name": "필드누락장소", "address_name": "서울시",
                    "category_name": "카페", "y": "37.5", "x": "127.0",
                    "place_url": "url", "id": "2",
                },
            ]
        }
        mock_get.return_value = fake_response

        result = search_places("카페", 37.5665, 126.978)

        # optional 필드가 없는 문서도 정규화된 응답 형식을 유지한다.
        assert len(result) == 2
        assert result[0]["name"] == "정상카페"
        assert set(result[1]) == {
            "name", "address", "category", "lat", "lng", "url", "distance", "kakaoId",
        }
        assert result[1]["distance"] == 0
        assert result[1]["address"] == "서울시"

    @patch("recommend.place.requests.get")
    def test_missing_coordinates_are_skipped_not_defaulted_to_zero(self, mock_get):
        """좌표(y, x) 자체가 없는 문서는 (0, 0) 같은 엉뚱한 기본값으로 채우지 말고
        그 항목을 건너뛰어야 한다. 위도/경도 0은 '틀린 값'이 아니라 '그럴듯해 보이는
        틀린 값'이라 조용히 섞이면 더 위험하다."""
        fake_response = Mock()
        fake_response.status_code = 200
        fake_response.json.return_value = {
            "documents": [
                {
                    "place_name": "좌표없는곳", "address_name": "서울시",
                    "category_name": "카페", "place_url": "url", "id": "1",
                    # y, x 자체가 없음
                },
                {
                    "place_name": "정상카페", "address_name": "서울시",
                    "category_name": "카페", "y": "37.5", "x": "127.0",
                    "place_url": "url", "id": "2",
                },
            ]
        }
        mock_get.return_value = fake_response

        result = search_places("카페", 37.5665, 126.978)
        assert len(result) == 1
        assert result[0]["name"] == "정상카페"

    @patch("recommend.place.requests.get")
    def test_all_invalid_place_documents_are_reported_as_bad_provider_response(self, mock_get):
        fake_response = Mock()
        fake_response.status_code = 200
        fake_response.json.return_value = {
            "documents": [{
                "place_name": "좌표가 잘못된 장소", "id": "1",
                "y": "999", "x": "127.0",
            }]
        }
        mock_get.return_value = fake_response

        with pytest.raises(PlaceSearchError):
            search_places("카페", 37.5665, 126.978)

    @patch("recommend.place.requests.get")
    def test_radius_is_clamped_to_kakao_max(self, mock_get):
        """카카오 로컬 API의 radius 상한(20000)을 넘는 값이 들어와도, 그대로
        보내지 말고 20000으로 잘라서 보내야 한다 (안 그러면 카카오가 400을 반환하고
        place.py는 그걸 '결과 없음'으로 조용히 삼켜버린다)."""
        fake_response = Mock()
        fake_response.status_code = 200
        fake_response.json.return_value = {"documents": []}
        mock_get.return_value = fake_response

        search_places("카페", 37.5665, 126.978, radius=25000)

        sent_params = mock_get.call_args.kwargs["params"]
        assert sent_params["radius"] == 20000

    @patch("recommend.place.requests.get")
    def test_sort_parameter_defaults_to_accuracy_and_can_use_distance(self, mock_get):
        fake_response = Mock()
        fake_response.status_code = 200
        fake_response.json.return_value = {"documents": []}
        mock_get.return_value = fake_response

        search_places("카페", 37.5665, 126.978)
        search_places("지하철역", 37.5665, 126.978, sort="distance")

        sent_sorts = [
            call.kwargs["params"]["sort"] for call in mock_get.call_args_list
        ]
        assert sent_sorts == ["accuracy", "distance"]


# ── 3-2. weather.py 네트워크 장애 대응 테스트 ────────────────

class TestWeatherNetworkFailure:
    @patch("recommend.weather.requests.get", side_effect=requests.exceptions.Timeout)
    def test_get_weather_timeout_degrades_gracefully(self, mock_get):
        result = get_weather(37.5665, 126.978)
        assert result["condition"] == "unknown"

    @patch("recommend.weather.requests.get", side_effect=requests.exceptions.ConnectionError)
    def test_get_weather_connection_error_degrades_gracefully(self, mock_get):
        result = get_weather(37.5665, 126.978)
        assert result["condition"] == "unknown"

    @patch("recommend.weather.requests.get")
    def test_get_weather_malformed_json_degrades_gracefully(self, mock_get):
        fake_response = Mock()
        fake_response.status_code = 200
        fake_response.json.side_effect = ValueError("bad json")
        mock_get.return_value = fake_response
        result = get_weather(37.5665, 126.978)
        assert result["condition"] == "unknown"

    @patch("recommend.weather.requests.get")
    def test_get_weather_unexpected_structure_degrades_gracefully(self, mock_get):
        """OpenWeatherMap이 예상과 다른 구조(weather 필드 없음 등)로 응답해도
        KeyError가 위로 전파되지 않아야 한다."""
        fake_response = Mock()
        fake_response.status_code = 200
        fake_response.json.return_value = {"main": {"temp": 20}}  # "weather" 키 없음
        mock_get.return_value = fake_response
        result = get_weather(37.5665, 126.978)
        assert result["condition"] == "unknown"

    @patch("recommend.weather.requests.get", side_effect=requests.exceptions.Timeout)
    def test_get_weather_forecast_timeout_degrades_gracefully(self, mock_get):
        result = get_weather_forecast(37.5665, 126.978, "2026-09-01T12:00:00")
        assert result["condition"] == "unknown"

    @patch("recommend.weather.requests.get")
    def test_get_weather_forecast_malformed_json_degrades_gracefully(self, mock_get):
        fake_response = Mock()
        fake_response.status_code = 200
        fake_response.json.side_effect = ValueError("bad json")
        mock_get.return_value = fake_response
        result = get_weather_forecast(37.5665, 126.978, "2026-09-01T12:00:00")
        assert result["condition"] == "unknown"

def _make_barely_touching_scenario():
    """
    회귀 테스트용 시나리오 생성기.

    u0,u1,u2: 넉넉하게 겹치는 3인 클러스터 (반경 약 1950m짜리 교집합)
    u3: 그 클러스터 경계를 딱 50m만 파고드는 원 (반경 환산 시 약 65m — 스치는 수준)
    u4: 완전히 무관한 먼 지점 (부산) — 어떤 조합에도 안 겹침

    u0~u3의 4인 조합은 "허수 교집합"(반경 65m)을 만들고, u0,u1,u2 3인 조합은
    "실제로 쓸만한 교집합"(반경 1950m)을 만든다. 인원 수만 보고 고르면 틀린 답이 나오고,
    실사용 가능성까지 봐야 맞는 답(3인 클러스터)이 나오는 상황을 재현한다.
    """
    u0 = {"lat": 37.5665, "lng": 126.9780, "radius": 2000}
    u1 = {"lat": 37.5670, "lng": 126.9785, "radius": 2000}
    u2 = {"lat": 37.5660, "lng": 126.9775, "radius": 2000}

    cluster3 = get_intersection_shape([u0, u1, u2])
    bounds = cluster3.bounds
    outside_x = bounds[2] + 500
    outside_y = (bounds[1] + bounds[3]) / 2
    dist_to_cluster = Point(outside_x, outside_y).distance(cluster3)

    u3_lat, u3_lng = utm_to_latlon(outside_x, outside_y)
    u3 = {"lat": u3_lat, "lng": u3_lng, "radius": dist_to_cluster + 50}  # 50m만 파고듦

    u4 = {"lat": 35.1796, "lng": 129.0756, "radius": 500}  # 부산, 완전 무관

    return u0, u1, u2, u3, u4


# ── 3-1. 스치는 수준(허수 교집합) 배제 회귀 테스트 ──────────

class TestUsableRadiusThreshold:
    """
    회귀 테스트: '원이 스치는 수준(허수 교집합)'이 인원 수만 보고
    실제 겹치는 것처럼 채택되던 버그의 재발 방지.
    """

    def test_calculate_intersection_rejects_barely_touching_overlap(self):
        """calculate_intersection이 반경 300m 미만의 허수 교집합을
        has_intersection: True로 잘못 보고하면 안 된다."""
        u0, u1, u2, u3, _ = _make_barely_touching_scenario()
        result = calculate_intersection([u0, u1, u2, u3])
        assert result["has_intersection"] is False
        assert result["search_radius"] is None

    def test_partial_intersection_skips_degenerate_larger_subset(self):
        """4/5명짜리 조합이 허수 교집합(반경 65m)이고, 3/5명짜리 조합이
        실제로 넉넉한 교집합(반경 약 1950m)이면, 인원 수가 많다는 이유로
        4/5를 고르면 안 되고 3/5의 실사용 가능한 조합을 골라야 한다."""
        u0, u1, u2, u3, u4 = _make_barely_touching_scenario()

        result = find_best_partial_intersection([u0, u1, u2, u3, u4])
        assert result is not None
        assert result["matched_count"] == 3  # 4가 아니라 3이어야 함
        assert result["total_count"] == 5
        assert result["search_radius"] > 1800  # 500(허수 floor)이 아니라 실제 넓은 반경


# ── 4. 교집합 계산 테스트 ─────────────────────────────────

class TestIntersection:
    def test_overlapping_circles_have_intersection(self):
        result = calculate_intersection(SEOUL_USERS_OVERLAP)
        assert result["has_intersection"] is True
        assert result["search_radius"] >= 500

    def test_far_apart_circles_have_no_intersection(self):
        result = calculate_intersection(SEOUL_USERS_NO_OVERLAP)
        assert result["has_intersection"] is False
        assert result["center_lat"] is None


# ── 4-1. 교집합 실패 시 "가장 많이 겹치는 지점" 안내 ─────────

class TestPartialIntersection:
    def test_two_users_no_partial_possible(self):
        """전체 인원이 2명이면, 그보다 작은 의미 있는 부분집합이 없으므로
        None이어야 한다 (설계 결함이 아니라 2명일 땐 원래 그런 것)."""
        assert find_best_partial_intersection(SEOUL_USERS_NO_OVERLAP) is None

    def test_three_users_finds_the_pair_that_overlaps(self):
        """A,B는 가깝고 C만 멀면 → A,B 둘이 겹치는 지점(2/3)을 찾아야 한다."""
        near_a = {"lat": 37.5665, "lng": 126.9780, "radius": 1000}
        near_b = {"lat": 37.5675, "lng": 126.9790, "radius": 1000}
        far_c = {"lat": 37.4979, "lng": 127.0276, "radius": 1000}

        result = find_best_partial_intersection([near_a, near_b, far_c])
        assert result is not None
        assert result["matched_count"] == 2
        assert result["total_count"] == 3
        assert result["search_radius"] >= 500

    def test_five_users_prefers_larger_matching_subset(self):
        """5명 중 4명이 겹치고 1명만 멀면 → 4/5를 찾아야 한다(2/5나 3/5로 안주하면 안 됨)."""
        near = [
            {"lat": 37.5665, "lng": 126.9780, "radius": 1500},
            {"lat": 37.5670, "lng": 126.9785, "radius": 1500},
            {"lat": 37.5660, "lng": 126.9775, "radius": 1500},
            {"lat": 37.5668, "lng": 126.9782, "radius": 1500},
        ]
        far = {"lat": 35.1796, "lng": 129.0756, "radius": 1500}  # 부산

        result = find_best_partial_intersection(near + [far])
        assert result is not None
        assert result["matched_count"] == 4
        assert result["total_count"] == 5

    def test_no_pair_overlaps_returns_none(self):
        """어떤 두 명도 서로 안 겹치면(진짜 극단적 상황), 억지로 답 있는 척 하지 말고
        None을 반환해서 일반 안내 메시지로 폴백해야 한다."""
        users = [
            {"lat": 37.5665, "lng": 126.9780, "radius": 300},   # 서울시청
            {"lat": 35.1796, "lng": 129.0756, "radius": 300},   # 부산
            {"lat": 33.4996, "lng": 126.5312, "radius": 300},   # 제주
            {"lat": 37.4563, "lng": 126.7052, "radius": 300},   # 인천
        ]
        assert find_best_partial_intersection(users) is None

    def test_tie_break_prefers_larger_area_not_first_found(self):
        """같은 인원 수(k)로 겹치는 조합이 여러 개면, 탐색 순서상 먼저 찾은 게 아니라
        교집합 면적이 가장 넓은 조합을 골라야 한다."""
        u0 = {"lat": 37.5665, "lng": 126.9780, "radius": 2000}
        u1 = {"lat": 37.5670, "lng": 126.9785, "radius": 2000}
        u2 = {"lat": 37.5660, "lng": 126.9775, "radius": 2000}
        u3 = {"lat": 37.5668, "lng": 126.9782, "radius": 2000}  # (0,1,2,3)이 가장 넓게 겹침
        u4 = {"lat": 37.5620, "lng": 126.9820, "radius": 700}   # 이 사람이 끼면 항상 좁게 겹침

        result = find_best_partial_intersection([u0, u1, u2, u3, u4])
        assert result["matched_count"] == 4
        # (0,1,2,3) 조합의 면적에서 역산되는 search_radius여야 함 (u4가 낀 조합들보다 훨씬 큼)
        assert result["search_radius"] > 1800


# ── 4-2. 지하철역 선택 — 폴리곤 경계 대신 centroid 최근접 ─────

class TestMidpointStationSelection:
    def test_prefers_station_closer_to_centroid_over_strict_polygon_containment(self):
        """회귀 방지: 렌즈 모양 교집합의 뾰족한 끝(경계 안이지만 중심에서 1km+ 떨어짐)에
        있는 역보다, 경계 밖이라도 중심(공정한 지점)에 훨씬 가까운 역을 골라야 한다.
        역은 최종 추천 장소가 아니라 라벨/정렬 기준일 뿐이므로, 엄격한 폴리곤 포함
        여부보다 중심과의 거리가 더 적합한 기준이다."""
        users = [
            {"lat": 37.5665, "lng": 126.9780, "radius": 1500},
            {"lat": 37.5745, "lng": 126.9780, "radius": 1500},
        ]

        from recommend.intersection import get_intersection_shape
        shape = get_intersection_shape(users)
        c = shape.centroid

        # 렌즈의 뾰족한 끝(경계 안, 중심에서 멂)
        exterior_pts = list(shape.exterior.coords)
        farthest = max(exterior_pts, key=lambda p: (p[0] - c.x) ** 2 + (p[1] - c.y) ** 2)
        inward_x = c.x + (farthest[0] - c.x) * 0.97
        inward_y = c.y + (farthest[1] - c.y) * 0.97
        tip_lat, tip_lng = utm_to_latlon(inward_x, inward_y)

        # 중심 바로 옆(50m, 폴리곤 경계 밖일 수 있음)
        outside_lat, outside_lng = utm_to_latlon(c.x + 50, c.y)

        fake_stations = [
            {"name": "팁근처역", "lat": tip_lat, "lng": tip_lng, "category": "지하철역"},
            {"name": "중심근처역", "lat": outside_lat, "lng": outside_lng, "category": "지하철역"},
        ]
        with patch("recommend.midpoint.search_places", return_value=fake_stations):
            result = find_best_midpoint(users)

        assert result["area_name"] == "중심근처역"

    @patch("recommend.midpoint.search_places", return_value=[
        {"name": "먼역", "lat": 37.58, "lng": 126.978, "category": "지하철역"},
        {"name": "가까운역", "lat": 37.5666, "lng": 126.978, "category": "지하철역"},
    ])
    def test_station_search_requests_distance_sorted_candidates(self, mock_search):
        users = [
            {"lat": 37.5665, "lng": 126.9780, "radius": 1500},
            {"lat": 37.5670, "lng": 126.9785, "radius": 1500},
        ]

        result = find_best_midpoint(users)

        assert result["area_name"] == "가까운역"
        mock_search.assert_called_once()
        assert mock_search.call_args.kwargs["sort"] == "distance"
        assert mock_search.call_args.kwargs["size"] == 15
        assert len(result["nearby_stations"]) == 2

    @patch("recommend.midpoint.search_places", return_value=[
        {"name": "역A", "lat": 37.5666, "lng": 126.9780, "category": "지하철역"},
        {"name": "역A", "lat": 37.5667, "lng": 126.9781, "category": "지하철역"},
        {"name": "역B", "lat": 37.5668, "lng": 126.9782, "category": "지하철역"},
        {"name": "역C", "lat": 37.5669, "lng": 126.9783, "category": "지하철역"},
        {"name": "역D", "lat": 37.5670, "lng": 126.9784, "category": "지하철역"},
    ])
    def test_selects_up_to_three_unique_nearby_stations(self, mock_search):
        users = [
            {"lat": 37.5665, "lng": 126.9780, "radius": 1500},
            {"lat": 37.5670, "lng": 126.9785, "radius": 1500},
        ]

        result = find_best_midpoint(users)

        station_names = [station["area_name"] for station in result["nearby_stations"]]
        assert result["area_name"] == station_names[0]
        assert len(station_names) == 3
        assert set(station_names) == {"역A", "역B", "역C"}

    @patch("app.search_places")
    def test_station_search_supplements_center_and_still_filters_intersection(
        self, mock_search
    ):
        users = [
            {"lat": 37.5665, "lng": 126.9780, "radius": 3000},
            {"lat": 37.5675, "lng": 126.9790, "radius": 3000},
        ]
        intersection = calculate_intersection(users)
        shape = get_intersection_shape(users)
        station_lat, station_lng = users[0]["lat"], users[0]["lng"]
        in_intersection = [
            fake_place("역주변카페1", 37.5666, 126.9781, category="음식점 > 카페"),
            fake_place("역주변카페2", 37.5667, 126.9782, category="음식점 > 카페"),
        ]
        outside_intersection = fake_place(
            "역밖카페", 37.60, 127.05, category="음식점 > 카페",
        )
        mock_search.side_effect = [[], in_intersection + [outside_intersection]]

        result = app_module._search_and_filter(
            "카페",
            intersection["center_lat"],
            intersection["center_lng"],
            intersection["search_radius"],
            shape,
            stations=[{
                "area_name": "기준역",
                "center_lat": station_lat,
                "center_lng": station_lng,
            }],
        )

        assert mock_search.call_count == 2
        assert mock_search.call_args_list[0].args[1:3] == (
            intersection["center_lat"], intersection["center_lng"],
        )
        assert mock_search.call_args_list[1].args[1:3] == (station_lat, station_lng)
        assert {place["name"] for place in result} == {
            "역주변카페1", "역주변카페2",
        }

    @patch("app.search_places")
    def test_places_rank_by_station_distance_then_intersection_center(
        self, mock_search
    ):
        users = [
            {"lat": 37.5665, "lng": 126.9780, "radius": 3000},
            {"lat": 37.5675, "lng": 126.9790, "radius": 3000},
        ]
        intersection = calculate_intersection(users)
        shape = get_intersection_shape(users)
        station_lat, station_lng = users[0]["lat"], users[0]["lng"]
        station_close = fake_place(
            "역에가깝지만중심에서먼곳", station_lat, station_lng,
            category="음식점 > 카페",
        )
        center_close = fake_place(
            "중심에가깝지만역에서먼곳",
            intersection["center_lat"], intersection["center_lng"],
            category="음식점 > 카페",
        )
        mock_search.side_effect = [[station_close, center_close], []]

        result = app_module._search_and_filter(
            "카페",
            intersection["center_lat"],
            intersection["center_lng"],
            intersection["search_radius"],
            shape,
            stations=[{
                "area_name": "기준역",
                "center_lat": station_lat,
                "center_lng": station_lng,
            }],
        )

        assert [place["name"] for place in result] == [
            "역에가깝지만중심에서먼곳",
            "중심에가깝지만역에서먼곳",
        ]

    @patch("app.search_places")
    def test_station_recommendations_are_spread_across_stations(self, mock_search):
        users = [
            {"lat": 37.5665, "lng": 126.9780, "radius": 3000},
            {"lat": 37.5675, "lng": 126.9790, "radius": 3000},
        ]
        intersection = calculate_intersection(users)
        shape = get_intersection_shape(users)
        stations = [
            {"area_name": "역A", "center_lat": 37.5660, "center_lng": 126.9770},
            {"area_name": "역B", "center_lat": 37.5680, "center_lng": 126.9800},
        ]
        station_a_places = [
            fake_place(
                f"A{i}", 37.5660 + i * 0.0001, 126.9770,
                category="음식점 > 카페",
            )
            for i in range(4)
        ]
        station_b_places = [
            fake_place(
                f"B{i}", 37.5680 + i * 0.0001, 126.9800,
                category="음식점 > 카페",
            )
            for i in range(4)
        ]
        mock_search.side_effect = [[], station_a_places, station_b_places]

        result = app_module._search_and_filter(
            "카페",
            intersection["center_lat"],
            intersection["center_lng"],
            intersection["search_radius"],
            shape,
            stations=stations,
        )

        names = [place["name"] for place in result]
        assert len(names) == 8
        assert names[:4] == ["A0", "B0", "A1", "B1"]
        assert all(place["nearest_station"] in {"역A", "역B"} for place in result)
        assert all(isinstance(place["station_distance_m"], int) for place in result)

    @patch("recommend.midpoint.search_places", return_value=[])
    def test_no_stations_found_returns_none(self, mock_search):
        users = [
            {"lat": 37.5665, "lng": 126.9780, "radius": 1500},
            {"lat": 37.5670, "lng": 126.9785, "radius": 1500},
        ]
        assert find_best_midpoint(users) is None


# ── 5. /recommend 엔드포인트 실패 케이스 ──────────────────

class TestRecommendEndpoint:
    def test_no_body_returns_400(self):
        client = make_client()
        res = client.post("/recommend", json={})
        assert res.status_code == 400
        assert res.get_json()["error"]

    def test_missing_content_type_returns_json_400_not_html(self):
        """Content-Type 헤더 없이 온 요청도 HTML 에러 페이지가 아니라 JSON 400을 받아야
        Flutter 클라이언트의 response.body jsonDecode가 깨지지 않는다."""
        client = make_client()
        res = client.post("/recommend", data="")
        assert res.status_code == 400
        assert res.content_type.startswith("application/json")
        assert res.get_json()["error"]

    def test_malformed_json_returns_json_400_not_html(self):
        client = make_client()
        res = client.post("/recommend", data="{invalid", content_type="application/json")
        assert res.status_code == 400
        assert res.get_json()["error"]

    def test_unknown_route_returns_json_404(self):
        client = make_client()
        res = client.get("/no-such-route")
        assert res.status_code == 404
        assert res.get_json()["error"]

    def test_single_user_returns_400(self):
        client = make_client()
        res = client.post("/recommend", json={"users": [SEOUL_USERS_OVERLAP[0]]})
        assert res.status_code == 400

    def test_missing_radius_returns_400_not_500(self):
        """radius 필드 누락 시 KeyError로 500이 나지 않고 400으로 깔끔하게 막혀야 한다"""
        client = make_client()
        res = client.post("/recommend", json={
            "users": [
                {"lat": 37.5, "lng": 127.0},
                {"lat": 37.5, "lng": 127.0, "radius": 1000},
            ],
            "category": "cafe",
        })
        assert res.status_code == 400
        assert "radius" in res.get_json()["error"]

    def test_negative_radius_returns_400(self):
        client = make_client()
        res = client.post("/recommend", json={
            "users": [
                {"lat": 37.5, "lng": 127.0, "radius": -100},
                {"lat": 37.5, "lng": 127.0, "radius": 1000},
            ],
            "category": "cafe",
        })
        assert res.status_code == 400

    def test_out_of_range_lat_returns_400(self):
        client = make_client()
        res = client.post("/recommend", json={
            "users": [
                {"lat": 137.5, "lng": 127.0, "radius": 1000},  # 위도 범위(-90~90) 밖
                {"lat": 37.5, "lng": 127.0, "radius": 1000},
            ],
            "category": "cafe",
        })
        assert res.status_code == 400

    def test_more_than_five_users_returns_400(self):
        client = make_client()
        users = SEOUL_USERS_OVERLAP * 3  # 6명
        res = client.post("/recommend", json={"users": users})
        assert res.status_code == 400

    def test_no_intersection_returns_200_with_flag(self):
        """전체 인원이 2명이라 부분 매칭 자체가 불가능한 경우 → 기본 안내 메시지로 폴백."""
        client = make_client()
        res = client.post("/recommend", json={
            "users": SEOUL_USERS_NO_OVERLAP, "category": "cafe",
        })
        assert res.status_code == 200
        body = res.get_json()
        assert body["hasIntersection"] is False
        assert body["places"] == []
        assert "partialMatch" not in body

    def test_no_intersection_with_three_users_returns_partial_match(self):
        """3인 중 2명이 겹치면(missing=1), 그 지점과 데이터를 응답에 포함하되
        메시지엔 정확한 비율(2/3)을 노출하지 않고 '거의 다 됐다'는 톤으로만 표현해야 한다.
        (누가 안 겹치는지는 말하지 않음 — user_index 같은 필드가 없어야 함)"""
        near_a = {"lat": 37.5665, "lng": 126.9780, "radius": 1000}
        near_b = {"lat": 37.5675, "lng": 126.9790, "radius": 1000}
        far_c = {"lat": 37.4979, "lng": 127.0276, "radius": 1000}

        client = make_client()
        res = client.post("/recommend", json={
            "users": [near_a, near_b, far_c], "category": "cafe",
        })
        assert res.status_code == 200
        body = res.get_json()
        assert body["hasIntersection"] is False
        assert body["partialMatch"]["matched_count"] == 2
        assert body["partialMatch"]["total_count"] == 3
        assert "2/3" not in body["message"]  # 정확한 비율은 메시지에 노출하지 않음
        assert "거의" in body["message"]      # missing=1 → '거의 다 됐다' 톤
        assert "user_index" not in body["partialMatch"]

    def test_partial_match_far_case_uses_softer_message(self):
        """격차가 큰 경우(missing>=2)에는 '거의 다 됐다'는 표현을 쓰면 안 된다.
        5명 중 2명만 겹치는(missing=3) 상황으로 검증."""
        cluster = [
            {"lat": 37.5665, "lng": 126.9780, "radius": 1000},
            {"lat": 37.5670, "lng": 126.9785, "radius": 1000},
        ]
        far_users = [
            {"lat": 37.4979, "lng": 127.0276, "radius": 500},
            {"lat": 35.1796, "lng": 129.0756, "radius": 500},
            {"lat": 33.4996, "lng": 126.5312, "radius": 500},
        ]

        client = make_client()
        res = client.post("/recommend", json={
            "users": cluster + far_users, "category": "cafe",
        })
        assert res.status_code == 200
        body = res.get_json()
        assert body["hasIntersection"] is False
        assert body["partialMatch"]["matched_count"] == 2
        assert body["partialMatch"]["total_count"] == 5
        assert "거의" not in body["message"]
        assert "2/5" not in body["message"]

    @patch("app.find_best_midpoint", return_value=None)
    @patch("app.get_weather", return_value={"condition": "clear", "temp": 20, "description": "맑음"})
    @patch("app.search_places")
    def test_less_than_two_places_returns_422(self, mock_search, mock_weather, mock_midpoint):
        mock_search.return_value = [fake_place("유일한장소", 37.5665, 126.978, category="음식점 > 카페")]
        client = make_client()
        res = client.post("/recommend", json={
            "users": SEOUL_USERS_OVERLAP, "category": "cafe",
        })
        assert res.status_code == 422
        assert res.get_json()["code"] == "INSUFFICIENT_PLACES"

    @patch("app.find_best_midpoint", return_value=None)
    @patch("app.get_weather", return_value={"condition": "clear", "temp": 20, "description": "맑음"})
    @patch("app.search_places", side_effect=PlaceSearchError("Kakao Local API request failed"))
    def test_provider_failure_returns_502_not_insufficient_places(
        self, mock_search, mock_weather, mock_midpoint
    ):
        client = make_client()
        res = client.post("/recommend", json={
            "users": SEOUL_USERS_OVERLAP, "category": "cafe",
        })

        assert res.status_code == 502
        assert res.get_json()["code"] == "PLACE_PROVIDER_UNAVAILABLE"

    @patch("app.find_best_midpoint", return_value=None)
    @patch("app.get_weather", return_value={"condition": "clear", "temp": 20, "description": "맑음"})
    @patch("app.search_places")
    def test_places_outside_intersection_are_not_recommended(
        self, mock_search, mock_weather, mock_midpoint
    ):
        mock_search.return_value = [
            fake_place("교집합밖카페", 37.60, 127.05, category="음식점 > 카페"),
            fake_place("교집합밖카페2", 37.61, 127.06, category="음식점 > 카페"),
        ]
        client = make_client()
        res = client.post("/recommend", json={
            "users": SEOUL_USERS_OVERLAP, "category": "cafe",
        })

        assert res.status_code == 422
        assert res.get_json()["code"] == "INSUFFICIENT_PLACES"

    @patch("app.find_best_midpoint", return_value=None)
    @patch("app.get_weather", return_value={"condition": "clear", "temp": 20, "description": "맑음"})
    @patch("app.search_places")
    def test_places_outside_category_are_not_recommended(
        self, mock_search, mock_weather, mock_midpoint
    ):
        mock_search.return_value = [
            fake_place("관광지1", 37.5665, 126.978, category="여행 > 관광명소"),
            fake_place("관광지2", 37.5666, 126.9781, category="여행 > 관광명소"),
        ]
        client = make_client()
        res = client.post("/recommend", json={
            "users": SEOUL_USERS_OVERLAP, "category": "cafe",
        })

        assert res.status_code == 422
        assert res.get_json()["code"] == "INSUFFICIENT_PLACES"

    @patch("app.find_best_midpoint", return_value=None)
    @patch("app.get_weather", return_value={"condition": "clear", "temp": 20, "description": "맑음"})
    @patch("app.search_places")
    def test_same_name_locations_are_not_collapsed_before_filtering(
        self, mock_search, mock_weather, mock_midpoint
    ):
        outside = fake_place("같은이름카페", 37.60, 127.05, category="음식점 > 카페")
        inside = fake_place("같은이름카페", 37.5665, 126.978, category="음식점 > 카페")
        outside["kakaoId"] = "outside-id"
        inside["kakaoId"] = "inside-id"
        other_inside = fake_place("근처카페", 37.5666, 126.9781, category="음식점 > 카페")
        mock_search.return_value = [outside, inside, other_inside]

        client = make_client()
        res = client.post("/recommend", json={
            "users": SEOUL_USERS_OVERLAP, "category": "cafe",
        })

        assert res.status_code == 200
        recommended_ids = [place["kakaoId"] for place in res.get_json()["places"]]
        assert "inside-id" in recommended_ids
        assert "outside-id" not in recommended_ids

    @patch("app.find_best_midpoint", return_value={
        "area_name": "종각역", "center_lat": 37.567, "center_lng": 126.978,
    })
    @patch("app.get_weather", return_value={"condition": "clear", "temp": 20, "description": "맑음"})
    @patch("app.search_places")
    def test_study_category_happy_path(self, mock_search, mock_weather, mock_midpoint):
        """study 카테고리로 요청 시 카공카페(노트북/작업 목적) 쿼리로 정상 변환되어
        결과가 오는지 확인"""
        mock_search.return_value = [
            fake_place("작업하기좋은카페", 37.5665, 126.978, category="음식점 > 카페"),
            fake_place("노트북족카페", 37.5666, 126.9781, category="음식점 > 카페"),
        ]
        client = make_client()
        res = client.post("/recommend", json={
            "users": SEOUL_USERS_OVERLAP, "category": "study",
        })
        assert res.status_code == 200
        body = res.get_json()
        assert body["hasIntersection"] is True
        assert len(body["places"]) == 2
        # 실제로 카카오에 넘어간 쿼리가 "카공"/"노트북" 계열인지 확인
        called_queries = [c.args[0] for c in mock_search.call_args_list]
        assert any(("카공" in q or "노트북" in q) for q in called_queries)

    @patch("app.find_best_midpoint", return_value={
        "area_name": "종각역", "center_lat": 37.567, "center_lng": 126.978,
    })
    @patch("app.get_weather", return_value={"condition": "clear", "temp": 20, "description": "맑음"})
    @patch("app.search_places")
    def test_legacy_search_query_field_still_works(self, mock_search, mock_weather, mock_midpoint):
        """category 없이 구버전 search_query만 보내는 요청도 계속 지원하는지 확인
        (map_screen.dart 수정 전까지 하위호환이 필요할 수 있음)"""
        mock_search.return_value = [
            fake_place("A", 37.5665, 126.978, category="음식점 > 한식"),
            fake_place("B", 37.5666, 126.9781, category="음식점 > 한식"),
        ]
        client = make_client()
        res = client.post("/recommend", json={
            "users": SEOUL_USERS_OVERLAP, "search_query": "한식",
        })
        assert res.status_code == 200