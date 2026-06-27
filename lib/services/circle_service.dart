import 'package:cloud_firestore/cloud_firestore.dart';

class CircleService {
  final _db = FirebaseFirestore.instance;

  // 내 원 저장
  Future<void> saveMyCircle({
    required String roomId,
    required String userId,
    required String userName,
    required double lat,
    required double lng,
    required double radius,
  }) async {
    await _db
        .collection('rooms')
        .doc(roomId)
        .collection('circles')
        .doc(userId)
        .set({
      'lat': lat,
      'lng': lng,
      'radius': radius,
      'userName': userName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // 내 원 단건 조회
  Future<Map<String, dynamic>?> getMyCircle({
    required String roomId,
    required String userId,
  }) async {
    final snap = await _db
        .collection('rooms')
        .doc(roomId)
        .collection('circles')
        .doc(userId)
        .get();
    return snap.exists ? snap.data() : null;
  }

  // 특정 멤버 원 실시간 구독
  Stream<Map<String, dynamic>?> watchPartnerCircle({
    required String roomId,
    required String partnerId,
  }) {
    return _db
        .collection('rooms')
        .doc(roomId)
        .collection('circles')
        .doc(partnerId)
        .snapshots()
        .map((snap) => snap.exists ? snap.data() : null);
  }

  // 메시지 전송
  Future<void> sendMessage({
    required String roomId,
    required String userId,
    required String userName,
    required String message,
  }) async {
    await _db
        .collection('rooms')
        .doc(roomId)
        .collection('messages')
        .add({
      'userId': userId,
      'userName': userName,
      'message': message,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // 메시지 실시간 구독
  Stream<List<Map<String, dynamic>>> watchMessages({
    required String roomId,
  }) {
    return _db
        .collection('rooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  // 방의 모든 원 일괄 조회
  Future<List<Map<String, dynamic>>> getAllCircles(String roomId) async {
    final snap = await _db
        .collection('rooms')
        .doc(roomId)
        .collection('circles')
        .get();
    return snap.docs.map((d) => {...d.data(), 'userId': d.id}).toList();
  }

  // 추천 장소 저장 + status voting으로 변경
  Future<void> savePlaces(
      String roomId, List<Map<String, dynamic>> places) async {
    await _db.collection('rooms').doc(roomId).set(
      {'places': places, 'status': 'voting', 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  // 장소 확정
  Future<void> confirmPlace(
      String roomId, Map<String, dynamic> place) async {
    await _db.collection('rooms').doc(roomId).set(
      {'confirmedPlace': place, 'status': 'confirmed'},
      SetOptions(merge: true),
    );
  }

  // 다시 그리기 — 이번 약속 전부 초기화, status waiting으로
  Future<void> resetRoom(String roomId) async {
    await _db.collection('rooms').doc(roomId).update({
      'status': 'waiting',
      'places': FieldValue.delete(),
      'confirmedPlace': FieldValue.delete(),
      'appointmentDate': FieldValue.delete(),
    });

    for (final col in ['circles', 'messages', 'votes']) {
      final snap = await _db
          .collection('rooms')
          .doc(roomId)
          .collection(col)
          .get();
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
  }
}