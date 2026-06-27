import 'package:cloud_firestore/cloud_firestore.dart';

class HistoryService {
  final _db = FirebaseFirestore.instance;

  // 히스토리 전체 구독 (historyId 포함)
  Stream<List<Map<String, dynamic>>> watchHistory(String roomId) {
    return _db
        .collection('rooms')
        .doc(roomId)
        .collection('history')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => {...d.data(), 'historyId': d.id}).toList());
  }

  // 특정 방문의 기록 실시간 구독
  Stream<List<Map<String, dynamic>>> watchRecords(
      String roomId, String historyId) {
    return _db
        .collection('rooms')
        .doc(roomId)
        .collection('history')
        .doc(historyId)
        .collection('records')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => {...d.data(), 'recordId': d.id}).toList());
  }

  // 기록 추가
  Future<void> addRecord({
    required String roomId,
    required String historyId,
    required String userId,
    required String userName,
    required String review,
  }) {
    return _db
        .collection('rooms')
        .doc(roomId)
        .collection('history')
        .doc(historyId)
        .collection('records')
        .add({
      'userId':    userId,
      'userName':  userName,
      'review':    review,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // 기록 삭제
  Future<void> deleteRecord(
      String roomId, String historyId, String recordId) {
    return _db
        .collection('rooms')
        .doc(roomId)
        .collection('history')
        .doc(historyId)
        .collection('records')
        .doc(recordId)
        .delete();
  }

  // 만남 기록 삭제 (하위 records 포함)
  Future<void> deleteHistoryEntry(String roomId, String historyId) async {
    final records = await _db
        .collection('rooms')
        .doc(roomId)
        .collection('history')
        .doc(historyId)
        .collection('records')
        .get();
    if (records.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final doc in records.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    await _db
        .collection('rooms')
        .doc(roomId)
        .collection('history')
        .doc(historyId)
        .delete();
  }
}
