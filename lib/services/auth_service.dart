import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

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
    // Firestore에 유저 정보 저장
    await _db.collection('users').doc(cred.user!.uid).set({
      'email': email,
      'userName': userName,
      'rooms': [],
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
}
