import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../backend.dart';
import '../config.dart';

class Session extends ChangeNotifier {
  User? user;
  String? role;
  String? email;
  String? authProvider;
  bool ready = false;
  bool busy = false;
  String? error;
  String? _heldError;

  Session() {
    FirebaseAuth.instance.authStateChanges().listen(_handle);
  }

  bool get signedIn => user != null && role != null;

  Future<void> _handle(User? next) async {
    user = next;
    if (next == null) {
      role = null;
      email = null;
      authProvider = null;
      error = _heldError;
      _heldError = null;
      ready = true;
      busy = false;
      notifyListeners();
      return;
    }
    busy = true;
    notifyListeners();
    try {
      final data = await Backend.call('syncUser', {});
      role = data['role']?.toString();
      email = data['email']?.toString();
      authProvider = data['authProvider']?.toString();
      await next.getIdToken(true);
      error = null;
    } on FirebaseFunctionsException catch (error) {
      _heldError = error.message ?? '로그인에 실패했습니다.';
      await FirebaseAuth.instance.signOut();
      return;
    } finally {
      busy = false;
      ready = true;
      notifyListeners();
    }
  }

  Future<void> signIn(String emailAddress, String password) async {
    error = null;
    busy = true;
    notifyListeners();
    final address = emailAddress.trim();
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: address,
        password: password,
      );
    } on FirebaseAuthException catch (failure) {
      final missing = failure.code == 'user-not-found' || failure.code == 'invalid-credential';
      if (AppConfig.useEmulators && missing && address.toLowerCase() == AppConfig.adminEmail) {
        try {
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: address,
            password: password,
          );
          return;
        } on FirebaseAuthException {
          error = '이메일 또는 비밀번호가 올바르지 않습니다.';
        }
      } else {
        error = '이메일 또는 비밀번호가 올바르지 않습니다.';
      }
      busy = false;
      notifyListeners();
    }
  }

  Future<void> startAnonymous() async {
    error = null;
    busy = true;
    notifyListeners();
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } on FirebaseAuthException {
      error = '로그인 없이 시작하지 못했습니다.';
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  Future<String?> changePassword(String currentPassword, String nextPassword) async {
    final current = FirebaseAuth.instance.currentUser;
    final address = current?.email;
    if (current == null || address == null || address.isEmpty) {
      return '이메일 계정에서만 비밀번호를 바꿀 수 있습니다.';
    }
    try {
      final credential = EmailAuthProvider.credential(
        email: address,
        password: currentPassword,
      );
      await current.reauthenticateWithCredential(credential);
      await current.updatePassword(nextPassword);
      return null;
    } on FirebaseAuthException {
      return '비밀번호를 바꾸지 못했습니다. 현재 비밀번호를 확인해 주세요.';
    }
  }
}
