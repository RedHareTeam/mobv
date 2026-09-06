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
        .collection('appointments')
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
        .collection('appointments')
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
        .collection('appointments')
        .doc(roomId)
        .collection('circles')
        .doc(partnerId)
        .snapshots()
        .map((snap) => snap.exists ? snap.data() : null);
  }

  // 약속의 모든 원 일괄 조회
  Future<List<Map<String, dynamic>>> getAllCircles(String roomId) async {
    final snap = await _db
        .collection('appointments')
        .doc(roomId)
        .collection('circles')
        .get();
    return snap.docs.map((d) => {...d.data(), 'userId': d.id}).toList();
  }

  // 추천 장소 저장 + status voting으로 변경
  Future<void> savePlaces(
    String roomId,
    List<Map<String, dynamic>> places,
  ) async {
    await _db.collection('appointments').doc(roomId).set({
      'places': places,
      'status': 'voting',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // 장소 확정
  Future<void> confirmPlace(String roomId, Map<String, dynamic> place) async {
    await _db.collection('appointments').doc(roomId).set({
      'confirmedPlace': place,
      'status': 'confirmed',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
