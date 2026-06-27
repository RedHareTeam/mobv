import requests
import os
from dotenv import load_dotenv

load_dotenv()

ODSAY_API_KEY = os.getenv("ODSAY_API_KEY")

def get_transit_time(origin_lat, origin_lng, dest_lat, dest_lng):
    """
    ODsay API로 대중교통 이동시간 계산
    반환: 분 단위 소요시간 (실패 시 None)
    """
    url = "https://api.odsay.com/v1/api/searchPubTransPathT"
    params = {
        "SX": origin_lng,
        "SY": origin_lat,
        "EX": dest_lng,
        "EY": dest_lat,
        "apiKey": ODSAY_API_KEY
    }

    try:
        response = requests.get(url, params=params, timeout=3)  # 5 → 3

        #print(response.status_code)
        #print(response.text[:500])

        data = response.json()
        paths = data.get("result", {}).get("path", [])
        if not paths:
            return None
        return paths[0]["info"]["totalTime"]
    except Exception:
        return None