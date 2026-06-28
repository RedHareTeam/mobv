import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  static const List<int> profileColorValues = [
    0xFF5865F2,
    0xFF5AD6C0,
    0xFF2E9BC8,
    0xFFFF7A59,
    0xFFFFC857,
    0xFF7C5CFF,
    0xFF22C55E,
    0xFFFF5EA8,
  ];

  // 현재 유저
  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // 회원가입
  Future<UserCredential> signUp({
    required String email,
    required String password,
    required String userName,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final profileColor = _profileColorForUid(cred.user!.uid);
    // Firestore에 유저 정보 저장
    await _db.collection('users').doc(cred.user!.uid).set({
      'email': email,
      'userName': userName,
      'profileColor': profileColor,
      'appointments': [],
      'createdAt': FieldValue.serverTimestamp(),
    });
    return cred;
  }

  // 로그인
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // 로그아웃
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // 유저 정보 가져오기
  Future<Map<String, dynamic>?> getUserInfo(String userId) async {
    final snap = await _db.collection('users').doc(userId).get();
    return snap.exists ? snap.data() : null;
  }

  // 유저 정보 실시간 구독 (로컬 캐시 즉시 반환)
  Stream<Map<String, dynamic>?> watchUserInfo(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((snap) => snap.exists ? snap.data() : null);
  }

  Future<void> updateProfileColor(String userId, int colorValue) async {
    final roomsSnap = await _db
        .collection('appointments')
        .where('members', arrayContains: userId)
        .get();

    final batch = _db.batch();
    batch.update(_db.collection('users').doc(userId), {
      'profileColor': colorValue,
    });
    for (final roomDoc in roomsSnap.docs) {
      batch.update(roomDoc.reference, {
        'memberProfiles.$userId.color': colorValue,
      });
    }
    await batch.commit();
  }

  int fallbackProfileColor(String userId) => _profileColorForUid(userId);

  int _profileColorForUid(String uid) {
    final hash = uid.codeUnits.fold<int>(0, (total, code) => total + code);
    return profileColorValues[hash % profileColorValues.length];
  }
}
