import 'package:cloud_firestore/cloud_firestore.dart';

/// 장소 선택(투표) 전담 서비스
class VoteService {
  final _db = FirebaseFirestore.instance;

  // 장소 선택 저장
  Future<void> selectPlace({
    required String roomId,
    required String userId,
    required String userName,
    required String placeId,
  }) async {
    await _db
        .collection('rooms')
        .doc(roomId)
        .collection('votes')
        .doc(userId)
        .set({
      'userId': userId,
      'userName': userName,
      'selectedPlaceId': placeId,
    }, SetOptions(merge: true));
  }

  // 투표 취소
  Future<void> clearVote({
    required String roomId,
    required String userId,
  }) async {
    await _db
        .collection('rooms')
        .doc(roomId)
        .collection('votes')
        .doc(userId)
        .delete();
  }

  // 투표 현황 실시간 구독
  Stream<List<Map<String, dynamic>>> watchVotes(String roomId) {
    return _db
        .collection('rooms')
        .doc(roomId)
        .collection('votes')
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }
}
