import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/date_coordination_model.dart';

class AppointmentService {
  final _db = FirebaseFirestore.instance;
  final _uuid = const Uuid();

  // 약속 생성
  Future<String> createAppointment({
    required String myUserId,
    required String myUserName,
    required int myProfileColor,
    String appointmentTitle = '',
    String category = 'cafe',
    int maxMembers = 99,
    DateTime? appointmentDate,
    List<DateTime>? candidateDates,
    bool isDateCoordination = false,
  }) async {
    final roomId = _uuid.v4().substring(0, 8);
    final inviteCode = _uuid.v4().substring(0, 6).toUpperCase();

    final status = isDateCoordination
        ? 'date_voting'
        : (appointmentDate == null ? 'waiting' : 'drawing');

    final candidateDateStrings = (candidateDates ?? [])
        .map((d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}')
        .toList();

    await _db.collection('appointments').doc(roomId).set({
      'createdBy': myUserId,
      'members': [myUserId],
      'memberProfiles': {
        myUserId: {'name': myUserName, 'color': myProfileColor},
      },
      'status': status,
      'inviteCode': inviteCode,
      'appointmentTitle': appointmentTitle,
      'category': category,
      'maxMembers': maxMembers,
      if (appointmentDate != null)
        'appointmentDate': Timestamp.fromDate(appointmentDate),
      'isDateCoordination': isDateCoordination,
      'candidateDates': candidateDateStrings,
      'selectedDate': null,
      'selectedTimeSlot': null,
      'allDatesCompleted': false,
      'allCirclesCompleted': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _db.collection('users').doc(myUserId).set({
      'appointments': FieldValue.arrayUnion([roomId]),
    }, SetOptions(merge: true));

    return roomId;
  }

  // 초대 코드로 약속 참여
  // 반환값: roomId(성공), 'FULL'(정원 초과), 'CLOSED'(참여 마감), null(코드 없음)
  Future<String?> joinAppointment({
    required String inviteCode,
    required String myUserId,
    required String myUserName,
    required int myProfileColor,
  }) async {
    final snap = await _db
        .collection('appointments')
        .where('inviteCode', isEqualTo: inviteCode)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;

    final roomDoc = snap.docs.first;
    final roomId = roomDoc.id;
    final roomRef = _db.collection('appointments').doc(roomId);
    final userRef = _db.collection('users').doc(myUserId);

    String? result;
    await _db.runTransaction((tx) async {
      final fresh = await tx.get(roomRef);
      final data = fresh.data()!;
      final members = List<String>.from(data['members'] ?? []);
      final maxMembers = data['maxMembers'] as int? ?? 99;
      final status = data['status'] as String? ?? 'waiting';

      if (members.contains(myUserId)) {
        result = roomId;
        return;
      }
      if (!_canJoinStatus(status)) {
        result = 'CLOSED';
        return;
      }
      if (members.length >= maxMembers) {
        result = 'FULL';
        return;
      }
      tx.update(roomRef, {
        'members': FieldValue.arrayUnion([myUserId]),
        'memberProfiles.$myUserId': {
          'name': myUserName,
          'color': myProfileColor,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // user doc도 같은 트랜잭션에서 merge set
      tx.set(userRef, {
        'appointments': FieldValue.arrayUnion([roomId]),
      }, SetOptions(merge: true));
      result = roomId;
    });

    return result;
  }

  bool _canJoinStatus(String status) {
    return status == 'waiting' ||
        status == 'date_voting' ||
        status == 'drawing' ||
        status == 'circleReady';
  }

  // ── 날짜 조율 관련 메서드 ──────────────────────────────────

  /// 멤버의 가능한 날짜/시간대 투표 저장
  Future<void> submitDateVote({
    required String roomId,
    required DateVote vote,
  }) async {
    await _db
        .collection('appointments')
        .doc(roomId)
        .collection('dateVotes')
        .doc(vote.userId)
        .set(vote.toMap());

    // 약속 문서 updatedAt 갱신
    await _db.collection('appointments').doc(roomId).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 특정 방의 날짜 투표 실시간 스트림
  Stream<List<DateVote>> watchDateVotes(String roomId) {
    return _db
        .collection('appointments')
        .doc(roomId)
        .collection('dateVotes')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => DateVote.fromFirestore(doc.id, doc.data()))
            .toList());
  }

  /// 방장의 최종 날짜 및 시간대 확정
  Future<void> confirmAppointmentDate({
    required String roomId,
    required DateTime confirmedDate,
    required String timeSlot,
  }) async {
    await _db.collection('appointments').doc(roomId).update({
      'appointmentDate': Timestamp.fromDate(confirmedDate),
      'selectedDate': '${confirmedDate.year}-${confirmedDate.month.toString().padLeft(2, '0')}-${confirmedDate.day.toString().padLeft(2, '0')}',
      'selectedTimeSlot': timeSlot,
      'status': 'drawing', // 날짜 확정 후 위치(원 그리기) 모드로 전환
      'allDatesCompleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // 내 약속 목록 실시간 구독
  Stream<List<Map<String, dynamic>>> watchMyAppointments(String userId) {
    return _db
        .collection('appointments')
        .where('members', arrayContains: userId)
        .snapshots()
        .map((snap) {
          final appointments = snap.docs
              .map((d) => _withAppointmentCompatibility(d.data(), d.id))
              .toList();
          appointments.sort((a, b) {
            Timestamp? ta = (a['updatedAt'] ?? a['createdAt']) as Timestamp?;
            Timestamp? tb = (b['updatedAt'] ?? b['createdAt']) as Timestamp?;
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });
          return appointments;
        });
  }

  // 단일 약속 실시간 구독
  Stream<Map<String, dynamic>?> watchAppointment(String roomId) {
    return _db
        .collection('appointments')
        .doc(roomId)
        .snapshots()
        .map(
          (snap) => snap.exists
              ? _withAppointmentCompatibility(snap.data()!, snap.id)
              : null,
        );
  }

  // 약속 정보 단건 조회
  Future<Map<String, dynamic>?> getAppointment(String roomId) async {
    final snap = await _db.collection('appointments').doc(roomId).get();
    return snap.exists
        ? _withAppointmentCompatibility(snap.data()!, snap.id)
        : null;
  }

  Map<String, dynamic> _withAppointmentCompatibility(
    Map<String, dynamic> data,
    String id,
  ) {
    final normalized = {...data, 'roomId': id, 'appointmentId': id};
    normalized['memberProfiles'] = _memberProfilesFrom(data);
    normalized['appointmentTitle'] =
        data['appointmentTitle'] ?? data['roomTitle'] ?? '';
    return normalized;
  }

  Map<String, dynamic> _memberProfilesFrom(Map<String, dynamic> data) {
    final rawProfiles = Map<String, dynamic>.from(
      data['memberProfiles'] as Map? ?? {},
    );
    final names = Map<String, dynamic>.from(data['memberNames'] as Map? ?? {});
    final colors = Map<String, dynamic>.from(
      data['memberColors'] as Map? ?? {},
    );
    final members = List<String>.from(data['members'] ?? []);
    return {
      for (final uid in members)
        uid: {
          'name':
              (rawProfiles[uid] is Map
                      ? (rawProfiles[uid] as Map)['name']
                      : null)
                  ?.toString() ??
              names[uid]?.toString() ??
              '',
          'color': rawProfiles[uid] is Map
              ? ((rawProfiles[uid] as Map)['color'] ?? colors[uid])
              : colors[uid],
        },
    };
  }

  // 장소 확정 히스토리 저장
  // 트랜잭션 대신 배치 사용 → confirmPlace와 같은 문서를 동시에 쓸 때 precondition 충돌 방지
  // 결정적 doc ID(placeId_ts)로 양쪽 클라이언트가 중복 저장해도 merge로 멱등 처리
  Future<void> saveConfirmHistory({
    required String roomId,
    required Map<String, dynamic> confirmedPlace,
    required List<String> members,
    required DateTime? appointmentDate,
  }) async {
    final roomSnap = await _db.collection('appointments').doc(roomId).get();
    final data = roomSnap.data() ?? {};
    if (data['historySaved'] == true) return;

    final placeId = confirmedPlace['kakaoId'] ?? 'unknown';
    final ts = appointmentDate?.millisecondsSinceEpoch ?? 0;
    final histRef = _db
        .collection('appointments')
        .doc(roomId)
        .collection('history')
        .doc('${placeId}_$ts');

    final batch = _db.batch();
    batch.set(histRef, {
      'confirmedPlace': confirmedPlace,
      'members': members,
      if (appointmentDate != null)
        'appointmentDate': Timestamp.fromDate(appointmentDate),
      'date': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(_db.collection('appointments').doc(roomId), {
      'historySaved': true,
    }, SetOptions(merge: true));
    await batch.commit();
  }

  Future<void> cleanupConfirmedAppointment(String roomId) async {
    final appointmentRef = _db.collection('appointments').doc(roomId);
    await appointmentRef.update({
      'places': FieldValue.delete(),
      'selectedDate': FieldValue.delete(),
      'selectedTimeSlot': FieldValue.delete(),
      'allDatesCompleted': FieldValue.delete(),
      'allCirclesCompleted': FieldValue.delete(),
      'maxMembers': FieldValue.delete(),
      'historySaved': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    for (final col in ['circles', 'messages', 'votes']) {
      await _deleteSubcollection(roomId, col);
    }
  }

  Future<void> deleteAppointment(String roomId) async {
    final roomRef = _db.collection('appointments').doc(roomId);
    final roomSnap = await roomRef.get();
    final members = roomSnap.exists
        ? List<String>.from(roomSnap.data()?['members'] ?? [])
        : <String>[];

    for (final col in ['circles', 'messages', 'votes', 'history']) {
      await _deleteSubcollection(roomId, col);
    }

    final batch = _db.batch();
    batch.delete(roomRef);
    for (final uid in members) {
      batch.update(_db.collection('users').doc(uid), {
        'appointments': FieldValue.arrayRemove([roomId]),
      });
    }
    await batch.commit();
  }

  // (레거시 호환 - 내부 리셋이 필요한 경우 직접 호출)
  Future<void> confirmAndReset({
    required String roomId,
    required Map<String, dynamic> confirmedPlace,
    required List<String> members,
    DateTime? appointmentDate,
  }) async {
    await saveConfirmHistory(
      roomId: roomId,
      confirmedPlace: confirmedPlace,
      members: members,
      appointmentDate: appointmentDate,
    );

    final roomRef = _db.collection('appointments').doc(roomId);
    final batch = _db.batch();
    batch.update(roomRef, {
      'status': 'waiting',
      'updatedAt': FieldValue.serverTimestamp(),
      'places': FieldValue.delete(),
      'confirmedPlace': FieldValue.delete(),
      'appointmentDate': FieldValue.delete(),
      'historySaved': FieldValue.delete(),
    });
    await batch.commit();

    for (final col in ['circles', 'messages', 'votes']) {
      await _deleteSubcollection(roomId, col);
    }
  }

  Future<void> _deleteSubcollection(String roomId, String col) async {
    final snap = await _db
        .collection('appointments')
        .doc(roomId)
        .collection(col)
        .get();
    // batch 한도 500개를 초과하지 않도록 400개씩 청크 처리
    const chunkSize = 400;
    for (int i = 0; i < snap.docs.length; i += chunkSize) {
      final chunk = snap.docs.skip(i).take(chunkSize);
      final batch = _db.batch();
      for (final doc in chunk) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  // 날짜 설정 후 drawing 상태로 전환
  Future<void> setDrawingStatus(String roomId, DateTime appointmentDate) async {
    await _db.collection('appointments').doc(roomId).update({
      'appointmentDate': Timestamp.fromDate(appointmentDate),
      'status': 'drawing',
      'updatedAt': FieldValue.serverTimestamp(),
      'historySaved': FieldValue.delete(),
    });
  }

  // 약속 나가기
  // - members에서 제거 + 활동 중(drawing/voting)이면 상태 초기화
  // - members가 0명이면 약속 + 서브컬렉션 전체 삭제
  Future<void> leaveAppointment({
    required String roomId,
    required String userId,
  }) async {
    final roomRef = _db.collection('appointments').doc(roomId);
    bool isRoomDeleted = false;
    bool needsSubReset = false;

    await _db.runTransaction((tx) async {
      final snap = await tx.get(roomRef);
      if (!snap.exists) return;

      final data = snap.data()!;
      final members = List<String>.from(data['members'] ?? []);
      final status = data['status'] as String? ?? 'waiting';
      members.remove(userId);

      isRoomDeleted = members.isEmpty;
      needsSubReset =
          !isRoomDeleted && (status == 'drawing' || status == 'voting');

      if (isRoomDeleted) {
        tx.delete(roomRef);
      } else {
        final update = <String, dynamic>{
          'members': members,
          'memberProfiles.$userId': FieldValue.delete(),
        };
        if (needsSubReset) {
          update['status'] = 'waiting';
          update['updatedAt'] = FieldValue.serverTimestamp();
          update['appointmentDate'] = FieldValue.delete();
          update['places'] = FieldValue.delete();
        }
        tx.update(roomRef, update);
      }
    });

    // 서브컬렉션 정리 (트랜잭션 밖에서)
    if (isRoomDeleted) {
      for (final col in ['circles', 'messages', 'votes', 'history']) {
        await _deleteSubcollection(roomId, col);
      }
    } else if (needsSubReset) {
      for (final col in ['circles', 'messages', 'votes']) {
        await _deleteSubcollection(roomId, col);
      }
    }

    await _db.collection('users').doc(userId).update({
      'appointments': FieldValue.arrayRemove([roomId]),
    });
  }

  // 만남 히스토리 구독
  Stream<List<Map<String, dynamic>>> watchHistory(String roomId) {
    return _db
        .collection('appointments')
        .doc(roomId)
        .collection('history')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  // 특정 서브컬렉션의 모든 문서를 일괄 삭제
  Future<void> deleteSubcollection(String roomId, String sub) async {
    final snap = await _db
        .collection('appointments')
        .doc(roomId)
        .collection(sub)
        .get();
    for (final doc in snap.docs) {
      await doc.reference.delete();
    }
  }
}
