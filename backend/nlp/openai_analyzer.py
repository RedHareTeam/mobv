import os
from openai import OpenAI
from dotenv import load_dotenv
import json

PLACE_TYPE_MAP = {
    "한식": "한식당",
    "파스타": "파스타집",
    "피자": "피자집",
    "라멘": "라멘집",
    "술": "술집",
    "카페": "카페",
    "바": "바",
    "이자카야": "이자카야",
    "스터디": "스터디카페",
    "햄버거": "햄버거",
    "초밥": "초밥",
    "스시": "초밥",
    "중식": "중식당",
    "고기": "고깃집",
    "삼겹살": "고깃집",
    "스테이크": "스테이크",
    "양식": "양식당",
    "베트남": "베트남음식",
    "쌀국수": "베트남음식",
    "국밥": "국밥",
    "회": "횟집",
    "브런치": "브런치카페",
}

FOOD_PLACE_MAP = {
    "라멘": "라멘집",
    "파스타": "파스타집",
    "피자": "피자집",
    "고기": "고깃집",
    "삼겹살": "고깃집",
    "소고기": "고깃집",
    "한식": "한식당",
    "한정식": "한정식",
    "햄버거": "햄버거",
    "타코": "타코",
    "초밥": "초밥",
    "스시": "초밥",
    "중식": "중식당",
    "짜장면": "중식당",
    "짬뽕": "중식당",
    "국밥": "국밥",
    "순대": "순대국",
    "곱창": "곱창",
    "회": "횟집",
    "해산물": "해산물",
    "스테이크": "스테이크",
    "양식": "양식당",
    "인도": "인도음식",
    "커리": "인도음식",
    "태국": "태국음식",
    "베트남": "베트남음식",
    "쌀국수": "베트남음식",
    "브런치": "브런치카페",
    "멕시칸": "멕시칸",
    "샐러드": "샐러드",
}

DESSERT_KEYWORDS = ["디저트", "케이크", "마카롱", "타르트", "와플"]
BAKERY_KEYWORDS  = ["빵", "베이커리", "크루아상", "스콘"]

MOOD_NORMALIZE = {
    "감성": "감성",
    "감성 있는": "감성",
    "분위기": "감성",
    "분위기 있는": "감성",
    "분위기 좋은": "감성",
    "조용한": "조용한",
    "조용": "조용한",
    "아늑한": "조용한",
    "작업": "작업",
    "노트북": "작업",
    "노트북 가능한": "작업",
    "노트북 사용": "작업",
    "작업할 수 있는": "작업",
    "콘센트": "작업",
    "편안한": "편안한",
    "편한": "편안한",
}


def detect_purpose(conversation):
    if any(word in conversation for word in ["노트북", "회의", "미팅", "업무", "협업"]):
        return "업무미팅"
    if any(word in conversation for word in ["기념일", "데이트"]):
        return "데이트"
    if any(word in conversation for word in ["술 한잔", "한잔 하자", "술이나", "한잔할"]):
        return "술자리"
    return "친목"


def has_strong_signal(conversation, keywords, threshold=2):
    return sum(conversation.count(k) for k in keywords) >= threshold


def detect_secondary_cafe_type(preferred_food):
    for food in preferred_food:
        if any(k in food for k in DESSERT_KEYWORDS):
            return "디저트카페"
        if any(k in food for k in BAKERY_KEYWORDS):
            return "베이커리카페"
    return None


def analyze_with_openai(messages):
    load_dotenv()
    client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

    conversation = "\n".join(
        f"[{m['sender']}] {m['message']}" for m in messages
    )

    senders = list(dict.fromkeys(m['sender'] for m in messages))
    sender_info = f"대화 참여자: {senders[0]}, {senders[1]}" if len(senders) >= 2 else ""

    purpose = detect_purpose(conversation)

    prompt = f"""
다음은 두 사람의 카카오톡 대화입니다.

{sender_info}

[예시1]
대화:
[A] 저번에 삼겹살 먹었으니까 이번엔 다른 거 먹자
[A] 파스타 먹고 감성 있는 카페 가자
[B] 좋아 조용한 데로 찾아볼게

올바른 분석:
{{
  "preferred_food": ["파스타"],
  "avoided_food": ["삼겹살"],
  "place_type": ["파스타집"],
  "secondary_place_type": ["카페"],
  "mood": ["감성", "조용한"]
}}

[예시2]
대화:
[A] 조용한 카페 어떠세요
[B] 좋아요 노트북 사용 가능한 카페 찾았어요

올바른 분석:
{{
  "preferred_food": [],
  "avoided_food": [],
  "place_type": ["카페"],
  "secondary_place_type": [],
  "mood": ["조용한", "작업"]
}}

[예시3]
대화:
[A] 라멘 먹고 디저트 카페 가자
[B] 오 좋아 케이크 땡긴다

올바른 분석:
{{
  "preferred_food": ["케이크", "디저트"],
  "avoided_food": [],
  "place_type": ["라멘집"],
  "secondary_place_type": ["카페"],
  "mood": []
}}

이제 아래 실제 대화를 분석해주세요:

대화:
{conversation}

[분석 규칙]

place_type 규칙:
- 1차 목적 장소만 1개 선택
- "밥 먹고 카페", "2차로 카페"처럼 순서 있으면 식당만 place_type, 카페는 secondary_place_type
- 반드시 아래 중에서만: 카페, 술집, 한식당, 파스타집, 라멘집, 피자집, 바, 스터디카페, 이자카야

secondary_place_type 규칙:
- 2차 장소 있으면 여기에 넣기
- 없으면 빈 배열

mood 규칙:
- 반드시 대화 전체를 읽고 장소 관련 표현 찾기
- "감성 있는", "감성 카페", "조용한 데", "분위기 좋은" → 추출
- "노트북 가능한", "노트북 사용", "작업할 수 있는" → "작업" 으로 추출
- 대화에 mood 표현이 있는데 빈 배열로 내면 오답
- 없으면 빈 배열

avoided_food 규칙:
- avoided는 preferred에 절대 포함 금지
- "저번에 ~먹었으니까", "~말고", "~많이 먹어서" → avoided
- "저번에 ~먹었으니까 이번엔" → 앞의 음식은 avoided, 뒤의 음식은 preferred
- 최근 대화 우선

JSON으로만 응답:
{{
  "preferred_food": [],
  "avoided_food": [],
  "place_type": [],
  "secondary_place_type": [],
  "mood": []
}}
"""

    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[{"role": "user", "content": prompt}],
        temperature=0.3
    )

    result = response.choices[0].message.content.strip()

    try:
        if result.startswith("```"):
            result = result.split("```")[1]
            if result.startswith("json"):
                result = result[4:]
        parsed = json.loads(result)

        parsed["place_type"] = [
            PLACE_TYPE_MAP.get(p, p)
            for p in parsed.get("place_type", [])
        ]
        parsed["secondary_place_type"] = [
            PLACE_TYPE_MAP.get(p, p)
            for p in parsed.get("secondary_place_type", [])
        ]

        preferred = parsed.get("preferred_food", [])
        avoided = parsed.get("avoided_food", [])

        import re
        rule_avoided = re.findall(r'저번에\s+(\S+)\s+먹었으니까', conversation)
        for food in rule_avoided:
            food = food.strip()
            if food not in avoided:
                avoided.append(food)
        parsed["avoided_food"] = avoided

        parsed["preferred_food"] = [f for f in preferred if f not in avoided]

        avoided_normalized = [f.strip() for f in avoided]
        parsed["preferred_food"] = [
            f for f in parsed["preferred_food"]
            if f.strip() not in avoided_normalized
        ]

        if parsed["preferred_food"]:
            top_food = parsed["preferred_food"][-1]
            if top_food in FOOD_PLACE_MAP:
                parsed["place_type"] = [FOOD_PLACE_MAP[top_food]]

        parsed["place_type"] = parsed["place_type"][:1]

        for food in avoided:
            bad_place = FOOD_PLACE_MAP.get(food)
            if bad_place and bad_place in parsed["place_type"]:
                parsed["place_type"] = [p for p in parsed["place_type"] if p != bad_place]

        if not parsed["place_type"] and parsed["preferred_food"]:
            top_food = parsed["preferred_food"][0]
            if top_food in FOOD_PLACE_MAP:
                parsed["place_type"] = [FOOD_PLACE_MAP[top_food]]

        parsed["mood"] = list(dict.fromkeys(
            MOOD_NORMALIZE.get(m, m) for m in parsed.get("mood", [])
        ))

        secondary = parsed.get("secondary_place_type", [])
        if secondary and secondary[0] == "카페":
            cafe_type = detect_secondary_cafe_type(parsed["preferred_food"])
            if cafe_type:
                parsed["secondary_place_type"] = [cafe_type]

        if not parsed.get("secondary_place_type") or parsed["secondary_place_type"] == ["카페"]:
            for keyword in DESSERT_KEYWORDS:
                if keyword in conversation:
                    parsed["secondary_place_type"] = ["디저트카페"]
                    break
            else:
                for keyword in BAKERY_KEYWORDS:
                    if keyword in conversation:
                        parsed["secondary_place_type"] = ["베이커리카페"]
                        break

        # search_query 생성
        main_place = parsed["place_type"][0] if parsed["place_type"] else "맛집"
        parsed["search_query"] = main_place

        parsed['purpose'] = purpose
        parsed['senders'] = senders
        return parsed

    except json.JSONDecodeError:
        return {
            "purpose": purpose,
            "preferred_food": [],
            "avoided_food": [],
            "place_type": [],
            "secondary_place_type": [],
            "mood": [],
            "search_query": "맛집",
            "senders": senders
        }