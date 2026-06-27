import re

def parse_kakao_txt(filepath):
    """
    카카오톡 txt 파일 파싱
    형식: [이름] [오전/오후 H:MM] 메서지
    반환: [{"date": "2026-03-19", "time": "17:07", "sender": "양승연", "message": "안녕"}, ...]
    """

    # 날짜 구분선 패턴
    date_line_pattern = re.compile(
        r'-+\s*(\d{4})년 (\d{1,2})월 (\d{1,2})일.*-+'
    )

    # 메시지 패턴
    message_pattern = re.compile(
        r'\[(.+?)\] \[(오전|오후) (\d{1,2}):(\d{2})\] (.+)'
    )

    # 스킵할 메시지
    SKIP_MESSAGES = {'사진', '동영상', '파일', '음성메시지', '연락처', '지도', '이모티콘'}

    messages = []
    current_date = None
    current_msg = None  # 멀티라인 처리용

    with open(filepath, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\n')

            # 날짜 구분선 처리
            date_match = date_line_pattern.match(line.strip())
            if date_match:
                if current_msg:
                    messages.append(current_msg)
                    current_msg = None
                year, month, day = date_match.groups()
                current_date = f"{year}-{int(month):02d}-{int(day):02d}"
                continue
            
            # 메시지 라인 처리
            msg_match = message_pattern.match(line.strip())
            if msg_match:
                # 이전 멀티라인 메시지 저장
                if current_msg:
                    messages.append(current_msg)
                    current_msg = None

                sender, ampm, hour, minute = msg_match.group(1,2,3,4)
                message = msg_match.group(5).strip()
                hour, minute = int(hour), int(minute)

                # 오전/오후 → 24시간제
                if ampm == '오후' and hour != 12:
                    hour += 12
                if ampm == '오전' and hour == 12:
                    hour = 0

                # 스킵 메시지 처리 ("사진 3장" 같은 것도 스킵)
                if any(message.startswith(skip) for skip in SKIP_MESSAGES):
                    continue

                current_msg = {
                    "date": current_date,
                    "time": f"{hour:02d}:{minute:02d}",
                    "sender": sender.strip(),
                    "message": message
                }

            else:

                # 멀티라인 메시지 이어붙이기
                stripped = line.strip()
                if current_msg and stripped:
                    current_msg["message"] += " " + stripped

    # 마지막 메시지 저장
    if current_msg:
        messages.append(current_msg)
    return messages

def get_senders(messages):
    """대화 참여자 목록 반환"""
    return list(set(m["sender"] for m in messages))


    

