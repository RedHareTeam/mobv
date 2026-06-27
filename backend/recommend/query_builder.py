from concurrent.futures import ThreadPoolExecutor, as_completed

# 카페 mood → 검색 prefix (카카오 API 직접 테스트 검증)
MOOD_CAFE_WORDS = {
    "감성":       "감성",
    "분위기 좋은": "분위기 좋은",
    "조용한":     "조용한",
    "작업":       "카공",
    "편안한":     None,
}

# place_type → 카카오 자연어 검색어
PLACE_TYPE_QUERY = {
    "라멘집":       "라멘",
    "파스타집":     "파스타",
    "피자집":       "피자",
    "한식당":       "한식",
    "고깃집":       "고기",
    "이자카야":     "이자카야",
    "술집":         "술집",
    "바":           "바",
    "스터디카페":   "스터디카페",
    "중식당":       "중식",
    "횟집":         "회",
    "초밥":         "스시",
    "베트남음식":   "쌀국수",
    "스테이크":     "스테이크",
    "양식당":       "양식",
    "햄버거":       "햄버거",
    "브런치카페":   "브런치",
    "국밥":         "국밥",
    "한정식":       "한정식",
    "디저트카페":   "디저트 카페",
    "베이커리카페": "베이커리 카페",
    "카페":         "카페",
}

# purpose + place_type → 카카오 검색어 prefix (직접 테스트 검증)
# 카페는 mood 우선이라 여기선 음식점/술집만
PURPOSE_QUERY = {
    ("데이트",   "음식점"): "데이트 맛집",
    ("술자리",   "술집"):   "야장",
}

CAFE_TYPES = {"카페", "디저트카페", "베이커리카페", "스터디카페", "브런치카페"}
BAR_TYPES  = {"술집", "바", "이자카야"}
DESSERT_WORDS = {"디저트", "케이크", "마카롱", "타르트", "와플", "빵", "베이커리", "크루아상", "스콘"}


def _get_place_category(place_type):
    if place_type in CAFE_TYPES:
        return "카페"
    if place_type in BAR_TYPES:
        return "술집"
    return "음식점"


def build_search_queries(place_type, mood_list, preferred_food=None, purpose=None):
    """
    카카오 API 검색 쿼리 리스트 반환 (우선순위 순, 병렬 검색용).

    우선순위:
    1. 카페류 → mood prefix 우선 ("감성 카페", "카공 카페" 등)
    2. purpose 매핑 있으면 → purpose 기반 쿼리 ("데이트 맛집", "야장")
    3. preferred_food 조합 가능하면 추가 쿼리
    4. 기본 place_type 쿼리
    """
    if not place_type:
        return ["맛집"]

    # ── 카페 계열: mood 우선 ───────────────────────────────
    if place_type in CAFE_TYPES:
        base = PLACE_TYPE_QUERY.get(place_type, place_type)
        # 디저트카페/베이커리카페/브런치카페는 고유 쿼리 그대로 사용
        # mood/purpose로 오버라이드하면 결과가 오히려 줄어듦
        if place_type in {"디저트카페", "베이커리카페", "브런치카페"}:
            return [base]
        # 일반 카페: purpose → mood → 기본 순
        if purpose == "업무미팅":
            # 작업 mood 있으면 카공 카페 1순위, 조용한 카페 폴백
            if "작업" in mood_list:
                return ["카공 카페", "조용한 카페"]
            return ["조용한 카페"]
        if purpose == "데이트":
            return ["감성 카페"]
        for mood in mood_list:
            prefix = MOOD_CAFE_WORDS.get(mood)
            if prefix:
                return [f"{prefix} {base}"]
        return [base]

    # ── 음식점/술집 계열 ──────────────────────────────────
    base_query = PLACE_TYPE_QUERY.get(place_type, place_type)
    category   = _get_place_category(place_type)

    # purpose 쿼리는 place_type이 범용일 때만 사용
    # 파스타집처럼 구체적인 경우 "데이트 맛집" 쿼리가
    # 무관한 음식점을 끌어와 필터 후 결과가 오히려 줄어듦
    GENERIC_PLACE_TYPES = {"한식당", "양식당", "술집", "바", "이자카야"}
    purpose_query = PURPOSE_QUERY.get((purpose, category))
    if purpose_query and place_type in GENERIC_PLACE_TYPES:
        queries = [purpose_query, base_query]
    else:
        queries = [base_query]

    # preferred_food 조합 (같은 카테고리 음식만, 디저트 제외)
    if preferred_food:
        for food in preferred_food:
            if not food or len(food) < 2:
                continue
            if any(d in food for d in DESSERT_WORDS):
                continue
            if food in base_query:
                continue
            queries.append(f"{food} {base_query}")
            break  # 1개만

    return queries


def filter_by_category(places, place_type):
    """카테고리 불일치 장소 필터링 (불일치 없으면 원본 반환)"""
    CATEGORY_RULES = {
        "한식당":       lambda c: "한식" in c,
        "카페":         lambda c: "카페" in c,
        "술집":         lambda c: any(k in c for k in ["술집", "주점", "호프"]),
        "라멘집":       lambda c: any(k in c for k in ["일식", "라멘"]),
        "초밥":         lambda c: any(k in c for k in ["일식", "초밥", "스시"]),
        "이자카야":     lambda c: any(k in c for k in ["일식", "이자카야", "주점"]),
        "파스타집":     lambda c: (any(k in c for k in ["파스타", "이탈리안", "이탈리아"]) or c == "음식점 > 양식") and not any(k in c for k in ["피자", "멕시칸", "카페", "치킨", "술집", "일식", "한식", "중식"]),
        "피자집":       lambda c: any(k in c for k in ["양식", "피자"]),
        "고깃집":       lambda c: any(k in c for k in ["고기", "구이", "한식"]),
        "중식당":       lambda c: "중식" in c,
        "횟집":         lambda c: any(k in c for k in ["해산물", "횟집", "일식"]),
        "디저트카페":   lambda c: "카페" in c,
        "베이커리카페": lambda c: "카페" in c,
        "스터디카페":   lambda c: "카페" in c,
        "브런치카페":   lambda c: "카페" in c,
    }

    rule = CATEGORY_RULES.get(place_type)
    if not rule:
        return places

    filtered = [p for p in places if rule(p.get("category", ""))]
    result = filtered if filtered else places

    # 프랜차이즈 패스트푸드 제거
    FRANCHISE_BLACKLIST = {
        "피자헛", "도미노피자", "피자마루", "피자스쿨", "피자알볼로",
        "미스터피자", "파파존스", "빨간모자피자", "피나치공", "역대급피자",
        "59쌀피자", "오구쌀피자", "청년피자", "반올림피자", "빽보이피자",
        "피자나라치킨공주", "피자나라",
        "맥도날드", "버거킹", "롯데리아", "KFC", "맘스터치", "쉐이크쉑",
        "노브랜드버거", "파이브가이즈", "슈퍼두퍼",
    }
    if place_type in {"피자집", "햄버거"}:
        filtered2 = [p for p in result if not any(b in p["name"] for b in FRANCHISE_BLACKLIST)]
        result = filtered2 if filtered2 else result

    return result


def search_with_multi_query(search_fn, queries, lat, lng, radius, size_per_query=8):
    """쿼리 여러 개를 병렬 검색해서 중복 제거 후 합산."""
    if len(queries) == 1:
        return search_fn(queries[0], lat, lng, radius=radius, size=size_per_query)

    results_map = {}  # kakaoId → place

    def fetch(q):
        return search_fn(q, lat, lng, radius=radius, size=size_per_query)

    with ThreadPoolExecutor(max_workers=len(queries)) as executor:
        futures = {executor.submit(fetch, q): q for q in queries}
        for future in as_completed(futures):
            try:
                for place in future.result():
                    pid = place.get("kakaoId") or place["name"]
                    if pid not in results_map:
                        results_map[pid] = place
            except Exception as e:
                print(f"멀티쿼리 검색 오류: {e}")

    return list(results_map.values())