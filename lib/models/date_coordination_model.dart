import 'package:cloud_firestore/cloud_firestore.dart';

/// 시간대 구간 정의
enum TimeSlot {
  lunch('점심', '11:00 ~ 14:00', '🍱'),
  afternoon('오후', '14:00 ~ 17:00', '☕'),
  dinner('저녁', '17:00 ~ 20:00', '🍽️'),
  night('야간', '20:00 이후', '🌙');

  final String label;
  final String timeRange;
  final String emoji;

  const TimeSlot(this.label, this.timeRange, this.emoji);

  static TimeSlot? fromKey(String key) {
    for (final slot in TimeSlot.values) {
      if (slot.name == key) return slot;
    }
    return null;
  }
}

/// 멤버 1인의 날짜/시간대 투표 데이터
class DateVote {
  final String userId;
  final String userName;
  final int profileColor;
  final List<String> availableDates; // 'yyyy-MM-dd' 형태 리스트
  final List<String> availableTimeSlots; // TimeSlot.name 리스트
  final DateTime? updatedAt;

  const DateVote({
    required this.userId,
    required this.userName,
    required this.profileColor,
    required this.availableDates,
    required this.availableTimeSlots,
    this.updatedAt,
  });

  factory DateVote.fromFirestore(String userId, Map<String, dynamic> data) {
    final rawDates = List<dynamic>.from(data['availableDates'] ?? []);
    final rawSlots = List<dynamic>.from(data['availableTimeSlots'] ?? []);
    final ts = data['updatedAt'] as Timestamp?;

    return DateVote(
      userId: userId,
      userName: data['userName'] as String? ?? '멤버',
      profileColor: (data['profileColor'] as num?)?.toInt() ?? 0xFF5865F2,
      availableDates: rawDates.map((e) => e.toString()).toList(),
      availableTimeSlots: rawSlots.map((e) => e.toString()).toList(),
      updatedAt: ts?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userName': userName,
      'profileColor': profileColor,
      'availableDates': availableDates,
      'availableTimeSlots': availableTimeSlots,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

/// 날짜별 투표 집계 결과 (추천 순위 산출용)
class DateSlotAggregate {
  final String dateString; // 'yyyy-MM-dd'
  final DateTime dateTime;
  final List<String> memberUserIds; // 해당 날짜에 가능한 멤버 uid 목록
  final Map<TimeSlot, List<String>> timeSlotMembers; // 시간대별 가능한 멤버 uid 목록

  DateSlotAggregate({
    required this.dateString,
    required this.dateTime,
    required this.memberUserIds,
    required this.timeSlotMembers,
  });

  int get memberCount => memberUserIds.length;

  /// 가장 많은 멤버가 선택한 최적 시간대 슬롯 반환
  TimeSlot? get mostPopularSlot {
    TimeSlot? bestSlot;
    int maxCount = -1;
    for (final entry in timeSlotMembers.entries) {
      if (entry.value.length > maxCount) {
        maxCount = entry.value.length;
        bestSlot = entry.key;
      }
    }
    return bestSlot;
  }
}
