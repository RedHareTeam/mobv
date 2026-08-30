import requests
import os
from datetime import datetime, timezone
from dotenv import load_dotenv

load_dotenv()

OPENWEATHER_API_KEY = os.getenv("OPENWEATHER_API_KEY")
OPENWEATHER_URL = "https://api.openweathermap.org/data/2.5/weather"
OPENWEATHER_FORECAST_URL = "https://api.openweathermap.org/data/2.5/forecast"


def _classify_weather(weather_id, description, temp):
    if weather_id < 300:
        condition = "thunder"
    elif weather_id < 600:
        condition = "rain"
    elif weather_id < 700:
        condition = "snow"
    elif weather_id == 800:
        condition = "clear"
    else:
        condition = "clouds"
    return {"condition": condition, "temp": round(temp, 1), "description": description}


FORECAST_WINDOW_DAYS = 5  # OpenWeatherMap 무료 플랜 최대 예보 범위


def get_weather_forecast(lat, lng, date_str):
    """약속 날짜의 예보 날씨 반환 (OpenWeatherMap 5일 예보).
    5일 초과 시 예보 불가 → condition: unknown 반환.
    """
    try:
        target_dt = datetime.fromisoformat(date_str.replace('Z', '+00:00'))
        if target_dt.tzinfo is None:
            target_dt = target_dt.replace(tzinfo=timezone.utc)
    except Exception:
        return {"condition": "unknown", "temp": 0, "description": "날짜 형식 오류"}

    now = datetime.now(tz=timezone.utc)
    delta_days = (target_dt - now).total_seconds() / 86400

    # 무료 플랜 예보 범위 초과 → 날씨 정보 제공 불가
    if delta_days > FORECAST_WINDOW_DAYS or delta_days < -1:
        return {"condition": "unknown", "temp": 0, "description": "예보 범위 초과"}

    params = {
        "lat": lat, "lon": lng,
        "appid": OPENWEATHER_API_KEY,
        "units": "metric", "lang": "kr",
    }

    try:
        response = requests.get(OPENWEATHER_FORECAST_URL, params=params, timeout=5)
    except requests.exceptions.RequestException as e:
        # place.py의 search_places와 동일한 degrade 패턴: 날씨는 참고용 정보라
        # 요청 전체를 막을 이유가 없다. 조용히 "알 수 없음"으로 내려준다.
        print(f"날씨 예보 API 오류: {e}")
        return {"condition": "unknown", "temp": 0, "description": "날씨 정보 없음"}

    if response.status_code != 200:
        return {"condition": "unknown", "temp": 0, "description": "날씨 정보 없음"}

    try:
        forecasts = response.json().get("list", [])
    except ValueError as e:
        print(f"날씨 예보 응답 파싱 오류: {e}")
        return {"condition": "unknown", "temp": 0, "description": "날씨 정보 없음"}

    if not forecasts:
        return {"condition": "unknown", "temp": 0, "description": "날씨 정보 없음"}

    # 목표 날짜와 가장 가까운 예보 항목 선택
    best = min(
        forecasts,
        key=lambda f: abs(datetime.fromtimestamp(f['dt'], tz=timezone.utc) - target_dt),
    )

    try:
        return _classify_weather(
            best["weather"][0]["id"],
            best["weather"][0]["description"],
            best["main"]["temp"],
        )
    except (KeyError, IndexError, TypeError) as e:
        # OpenWeatherMap이 예상과 다른 구조로 응답해도 예외가 위로 전파되지 않게 한다
        print(f"날씨 예보 필드 파싱 오류: {e}")
        return {"condition": "unknown", "temp": 0, "description": "날씨 정보 없음"}


def get_weather(lat, lng):
    """현재 날씨 정보 반환"""
    params = {
        "lat": lat, "lon": lng,
        "appid": OPENWEATHER_API_KEY,
        "units": "metric", "lang": "kr",
    }

    try:
        response = requests.get(OPENWEATHER_URL, params=params, timeout=5)
    except requests.exceptions.RequestException as e:
        print(f"날씨 API 오류: {e}")
        return {"condition": "unknown", "temp": 0, "description": "날씨 정보 없음"}

    if response.status_code != 200:
        return {"condition": "unknown", "temp": 0, "description": "날씨 정보 없음"}

    try:
        data = response.json()
        return _classify_weather(
            data["weather"][0]["id"],
            data["weather"][0]["description"],
            data["main"]["temp"],
        )
    except (ValueError, KeyError, IndexError, TypeError) as e:
        print(f"날씨 응답 파싱 오류: {e}")
        return {"condition": "unknown", "temp": 0, "description": "날씨 정보 없음"}