from concurrent.futures import ThreadPoolExecutor, as_completed

from recommend.place import PlaceSearchError

# 사용자 선택 카테고리 → 카카오 검색어
# 음식 이름 기반으로 단순화 (카카오 API 테스트 검증)
CATEGORY_QUERY = {
    # 카페
    "카페":     "카페",
    "디저트":   "디저트 카페",
    "맛집":     "맛집",

    # 음식
    "한식":     "한식",
    "마라탕":   "마라탕",
    "돈까스":   "돈까스",
    "라멘":     "라멘",
    "파스타":   ["파스타", "이탈리안"],
    "피자":     ["피자", "화덕피자"],
    "초밥":     "초밥",
    "고기":     "고기",
    "국밥":     "국밥",
    "분식":     "분식",

    # 술집
    "술집":     "술집",
    "이자카야": "이자카야",
    "바":       "바",

    # 스터디 (카공 — 노트북 들고 여럿이 모여 작업/공부하는 용도.
    # "스터디카페"라는 이름의 업종(1인 개인열람실형 공간대여업)과는 다르다.
    # 카카오에 "카공하기 좋은 카페"라는 별도 카테고리가 없으므로, 디저트와 같은
    # 방식으로 "카페"의 하위 개념으로 취급한다.
    #
    # 실제 API로 확인함(2026-08-30):
    # - "노트북 카페"는 결과 0개라 완전히 죽은 쿼리라서 제외.
    # - "카공 카페"(띄어쓰기) vs "카공카페"(붙여쓰기)는 결과가 완전히 동일 —
    #   카카오는 띄어쓰기를 구분하지 않는다.
    # - "카공카페" 단독으로는 스타벅스/투썸/파스쿠찌 같은 대형 프랜차이즈 위주로
    #   나오는데, "조용한 카페"를 같이 검색하면 개인 카페 위주로 결과가 넓어지고
    #   프랜차이즈 쏠림이 줄어든다(레거시 Chemeet 시스템도 동일한 조합을 썼음).
    "카공카페": ["카공카페", "조용한 카페"],
}

# 카테고리 필터링 규칙 (카카오 category_name 기준)
CATEGORY_RULES = {
    "카페":     lambda c: "카페" in c,
    "디저트":   lambda c: "카페" in c,
    "맛집":     lambda c: "음식점" in c and "카페" not in c,
    "한식":     lambda c: "한식" in c,
    "마라탕":   lambda c: "중식" in c,
    "돈까스":   lambda c: "돈까스" in c,
    "라멘":     lambda c: any(k in c for k in ["일식", "라멘"]),
    "파스타":   lambda c: any(k in c for k in ["파스타", "이탈리안"]),
    "피자":     lambda c: "피자" in c,
    "초밥":     lambda c: any(k in c for k in ["일식", "초밥", "스시"]),
    "고기":     lambda c: any(k in c for k in ["고기", "구이", "한식"]),
    "국밥":     lambda c: "한식" in c,
    "분식":     lambda c: "분식" in c,
    "술집":     lambda c: any(k in c for k in ["술집", "주점", "호프"]),
    "이자카야": lambda c: any(k in c for k in ["일식", "이자카야", "주점"]),
    "바":       lambda c: any(k in c for k in ["술집", "바", "주점"]),
    # 카페 하위 개념이라 "디저트"와 동일하게 일반 카페 카테고리 체크만 한다.
    # (스터디카페/스터디룸 같은 공간대여업 필터가 아님 — 그건 다른 목적의 장소다)
    "카공카페": lambda c: "카페" in c,
}

# 프랜차이즈 블랙리스트
PIZZA_BLACKLIST = {
    "피자헛", "도미노피자", "피자마루", "피자스쿨", "피자알볼로",
    "미스터피자", "파파존스", "빨간모자피자", "피나치공", "역대급피자",
    "59쌀피자", "오구쌀피자", "청년피자", "반올림피자", "빽보이피자",
    "피자나라치킨공주", "피자나라",
}

CAFE_BLACKLIST = {
    # 저가 커피 프랜차이즈
    "메가커피", "메가MGC커피",
    "컴포즈커피", "컴포즈",
    "빽다방",
    "더벤티",
    "매머드커피",
    "이디야",
    "카페베네",
    "탐앤탐스",
    "공차",
}

KOREAN_BLACKLIST = {
    # 빠른 식사용 프랜차이즈 (모임 부적합)
    "한솥", "본죽", "김밥천국", "롤링파스타",
}

STUDY_PLACE_BLACKLIST = {
    # 카공 장소로 부적합하다고 확인된 개별 장소명 (정확히 일치할 때만 제외)
    "적당",
}


def build_search_queries(category):
    """
    사용자가 선택한 카테고리 → 카카오 검색 쿼리 리스트 반환

    입력: category (예: "라멘", "카페", "술집")
    반환: ["라멘"] 또는 ["파스타", "이탈리안"] 형태의 쿼리 리스트
    """
    if not category:
        return ["맛집"]

    query = CATEGORY_QUERY.get(category, category)
    if isinstance(query, list):
        return query
    return [query]


def filter_by_category(places, category):
    """
    카테고리 불일치 장소와 블랙리스트 장소를 제외한다.
    """
    rule = CATEGORY_RULES.get(category)
    if not rule:
        return places

    result = [p for p in places if rule(p.get("category", ""))]

    # 피자/카페 카테고리 프랜차이즈 제거
    if category == "피자":
        result = [p for p in result if not any(b in p.get("name", "") for b in PIZZA_BLACKLIST)]

    if category in {"카페", "디저트", "카공카페"}:
        result = [p for p in result if not any(b in p.get("name", "") for b in CAFE_BLACKLIST)]

    if category == "카공카페":
        result = [
            p for p in result
            if p.get("name", "").strip() not in STUDY_PLACE_BLACKLIST
        ]

    if category == "한식":
        result = [p for p in result if not any(b in p.get("name", "") for b in KOREAN_BLACKLIST)]

    return result


def search_with_multi_query(search_fn, queries, lat, lng, radius, size_per_query=15):
    """
    쿼리 여러 개를 병렬 검색해서 중복 제거 후 합산
    현재는 단일 쿼리지만 확장 가능하도록 유지
    """
    if len(queries) == 1:
        return search_fn(queries[0], lat, lng, radius=radius, size=size_per_query)

    results_map = {}

    def fetch(q):
        return search_fn(q, lat, lng, radius=radius, size=size_per_query)

    with ThreadPoolExecutor(max_workers=len(queries)) as executor:
        futures = {executor.submit(fetch, q): q for q in queries}
        failures = []
        for future in as_completed(futures):
            try:
                for place in future.result():
                    pid = place.get("kakaoId") or place["name"]
                    if pid not in results_map:
                        results_map[pid] = place
            except PlaceSearchError as e:
                failures.append((futures[future], e))
                print(f"멀티쿼리 장소 검색 실패: query={futures[future]}, error={e}")

    if failures:
        raise failures[0][1]

    return list(results_map.values())