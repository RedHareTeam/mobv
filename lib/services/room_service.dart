import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class RoomService {
  final _db = FirebaseFirestore.instance;
  final _uuid = const Uuid();

  // 방 생성
  Future<String> createRoom({
    required String myUserId,
    required String myUserName,
    String roomTitle = '',
    String category = 'cafe',
    int maxMembers = 2,
  }) async {
    final roomId = _uuid.v4().substring(0, 8);
    final inviteCode = _uuid.v4().substring(0, 6).toUpperCase();

    await _db.collection('rooms').doc(roomId).set({
      'createdBy': myUserId,
      'members': [myUserId],
      'memberNames': {myUserId: myUserName},
      'status': 'waiting',
      'inviteCode': inviteCode,
      'roomTitle': roomTitle,
      'category': category,
      'maxMembers': maxMembers,
      'selectedDate': null,
      'selectedTimeSlot': null,
      'allDatesCompleted': false,
      'allCirclesCompleted': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _db.collection('users').doc(myUserId).update({
      'rooms': FieldValue.arrayUnion([roomId]),
    });

    return roomId;
  }

  // 초대 코드로 방 입장
  // 반환값: roomId(성공), 'FULL'(정원 초과), null(코드 없음)
  Future<String?> joinRoom({
    required String inviteCode,
    required String myUserId,
    required String myUserName,
  }) async {
    final snap = await _db
        .collection('rooms')
        .where('inviteCode', isEqualTo: inviteCode)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;

    final roomDoc = snap.docs.first;
    final roomId = roomDoc.id;
    final roomRef = _db.collection('rooms').doc(roomId);
    final userRef = _db.collection('users').doc(myUserId);

    String? result;
    await _db.runTransaction((tx) async {
      final fresh = await tx.get(roomRef);
      final data = fresh.data()!;
      final members = List<String>.from(data['members'] ?? []);
      final maxMembers = data['maxMembers'] as int? ?? 2;

      if (members.contains(myUserId)) {
        result = roomId;
        return;
      }
      if (members.length >= maxMembers) {
        result = 'FULL';
        return;
      }
      tx.update(roomRef, {
        'members': FieldValue.arrayUnion([myUserId]),
        'memberNames.$myUserId': myUserName,
      });
      // user doc도 같은 트랜잭션에서 업데이트 (불일치 방지)
      tx.update(userRef, {
        'rooms': FieldValue.arrayUnion([roomId]),
      });
      result = roomId;
    });

    return result;
  }

  // 내 방 목록 실시간 구독
  Stream<List<Map<String, dynamic>>> watchMyRooms(String userId) {
    return _db
        .collection('rooms')
        .where('members', arrayContains: userId)
        .snapshots()
        .map((snap) {
          final rooms = snap.docs
              .map((d) => {...d.data(), 'roomId': d.id})
              .toList();
          rooms.sort((a, b) {
            Timestamp? ta = (a['updatedAt'] ?? a['createdAt']) as Timestamp?;
            Timestamp? tb = (b['updatedAt'] ?? b['createdAt']) as Timestamp?;
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });
          return rooms;
        });
  }

  // 단일 방 실시간 구독
  Stream<Map<String, dynamic>?> watchRoom(String roomId) {
    return _db
        .collection('rooms')
        .doc(roomId)
        .snapshots()
        .map(
          (snap) => snap.exists ? {...snap.data()!, 'roomId': snap.id} : null,
        );
  }

  // 방 정보 단건 조회
  Future<Map<String, dynamic>?> getRoom(String roomId) async {
    final snap = await _db.collection('rooms').doc(roomId).get();
    return snap.exists ? {...snap.data()!, 'roomId': snap.id} : null;
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
    final roomSnap = await _db.collection('rooms').doc(roomId).get();
    final data = roomSnap.data() ?? {};
    if (data['historySaved'] == true) return;

    final placeId = confirmedPlace['kakaoId'] ?? 'unknown';
    final ts = appointmentDate?.millisecondsSinceEpoch ?? 0;
    final histRef = _db
        .collection('rooms')
        .doc(roomId)
        .collection('history')
        .doc('${placeId}_$ts');

    final batch = _db.batch();
    batch.set(histRef, {
      'confirmedPlace': confirmedPlace,
      'members': members,
      if (appointmentDate != null)
        'appointmentDate': Timestamp.fromDate(appointmentDate),
      if (data['intimacyScore'] != null) 'intimacyScore': data['intimacyScore'],
      'date': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(_db.collection('rooms').doc(roomId), {
      'historySaved': true,
    }, SetOptions(merge: true));
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

    final roomRef = _db.collection('rooms').doc(roomId);
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
        .collection('rooms')
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
    await _db.collection('rooms').doc(roomId).update({
      'appointmentDate': Timestamp.fromDate(appointmentDate),
      'status': 'drawing',
      'updatedAt': FieldValue.serverTimestamp(),
      'historySaved': FieldValue.delete(),
    });
  }

  // 방 나가기
  // - members에서 제거 + 활동 중(drawing/voting)이면 상태 초기화
  // - members가 0명이면 방 + 서브컬렉션 전체 삭제
  Future<void> leaveRoom({
    required String roomId,
    required String userId,
  }) async {
    final roomRef = _db.collection('rooms').doc(roomId);
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
          'memberNames.$userId': FieldValue.delete(),
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
      'rooms': FieldValue.arrayRemove([roomId]),
    });
  }

  // 만남 히스토리 구독
  Stream<List<Map<String, dynamic>>> watchHistory(String roomId) {
    return _db
        .collection('rooms')
        .doc(roomId)
        .collection('history')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  // 특정 서브컬렉션의 모든 문서를 일괄 삭제
  Future<void> deleteSubcollection(String roomId, String sub) async {
    final snap = await _db
        .collection('rooms')
        .doc(roomId)
        .collection(sub)
        .get();
    for (final doc in snap.docs) await doc.reference.delete();
  }
}
