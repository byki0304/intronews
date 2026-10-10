import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../backend.dart';
import '../config.dart';
import '../logic/identity.dart';

class Session extends ChangeNotifier {
  User? user;
  String? role;
  String? email;
  String? phone;
  String? nickname;
  String? authProvider;
  bool ready = false;
  bool busy = false;
  String? error;
  String? _heldError;

  Session() {
    FirebaseAuth.instance.authStateChanges().listen(_handle);
  }

  bool get signedIn => user != null && role != null;

  bool get hasNickname => nickname != null && nickname!.trim().isNotEmpty;

  bool get canChangePassword => authProvider == 'password' || authProvider == 'phone';

  String get maskedId => Identity.maskAccount(email: email, phone: phone);

  Future<void> _handle(User? next) async {
    user = next;
    if (next == null) {
      role = null;
      email = null;
      phone = null;
      nickname = null;
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
      email = _blankToNull(data['email']?.toString());
      phone = _blankToNull(data['phone']?.toString());
      authProvider = data['authProvider']?.toString();
      final stored = _blankToNull(data['nickname']?.toString());
      if (stored != null) {
        nickname = stored;
      } else if (!next.isAnonymous || nickname == null) {
        nickname = null;
      }
      if (hasNickname) {
        await Backend.call('ensurePrivateRecord', {});
      }
      await next.getIdToken(true);
      error = null;
    } on FirebaseFunctionsException catch (failure) {
      final address = next.email?.toLowerCase();
      final functionsMissing = !AppConfig.useEmulators && failure.code == 'not-found';
      if (functionsMissing && address == AppConfig.adminEmail) {
        role = 'admin';
        email = address;
        phone = null;
        authProvider = 'password';
        error = null;
      } else if (functionsMissing && next.isAnonymous) {
        role = 'member';
        email = null;
        phone = null;
        authProvider = 'anonymous';
        error = null;
      } else {
        _heldError = failure.message ?? '로그인에 실패했습니다.';
        await FirebaseAuth.instance.signOut();
        return;
      }
    } finally {
      busy = false;
      ready = true;
      notifyListeners();
    }
  }

  Future<void> signInWithEmail(String emailAddress, String password) async {
    final problem = Identity.emailError(emailAddress) ?? Identity.passwordError(password);
    if (problem != null) {
      _show(problem);
      return;
    }
    await _runAuth(() async {
      final address = emailAddress.trim();
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: address, password: password);
      } on FirebaseAuthException catch (failure) {
        final missing = failure.code == 'user-not-found' || failure.code == 'invalid-credential';
        if (AppConfig.useEmulators && missing && address.toLowerCase() == AppConfig.adminEmail) {
          await FirebaseAuth.instance.createUserWithEmailAndPassword(email: address, password: password);
          return;
        }
        rethrow;
      }
    });
  }

  Future<void> signUpWithEmail(String emailAddress, String password, String confirm) async {
    final problem = Identity.emailError(emailAddress) ?? Identity.confirmError(password, confirm);
    if (problem != null) {
      _show(problem);
      return;
    }
    await _runAuth(
      () => FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailAddress.trim(),
        password: password,
      ),
      phone: false,
    );
  }

  Future<void> signInWithPhone(String country, String national, String password) async {
    final problem = Identity.phoneError(country, national) ?? Identity.passwordError(password);
    if (problem != null) {
      _show(problem);
      return;
    }
    await _runAuth(
      () => FirebaseAuth.instance.signInWithEmailAndPassword(
        email: Identity.authEmailForPhone(country, national),
        password: password,
      ),
      phone: true,
    );
  }

  Future<void> signUpWithPhone(String country, String national, String password, String confirm) async {
    final problem = Identity.phoneError(country, national) ?? Identity.confirmError(password, confirm);
    if (problem != null) {
      _show(problem);
      return;
    }
    await _runAuth(
      () => FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: Identity.authEmailForPhone(country, national),
        password: password,
      ),
      phone: true,
    );
  }

  Future<void> signInWithGoogle() async {
    if (!kIsWeb) {
      _show('Google 로그인은 웹에서 사용할 수 있습니다.');
      return;
    }
    await _runAuth(() => FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider()));
  }

  Future<void> startWithoutLogin() async {
    await _runAuth(() => FirebaseAuth.instance.signInAnonymously());
  }

  Future<String?> submitNickname(String value) async {
    final problem = Identity.nicknameError(value);
    if (problem != null) return problem;
    final name = value.trim();
    final current = user;
    if (current == null) return '로그인이 필요합니다.';
    busy = true;
    notifyListeners();
    try {
      if (current.isAnonymous) {
        await Backend.call('ensurePrivateRecord', {});
        nickname = name;
        error = null;
        return null;
      }
      await Backend.call('saveNickname', {'nickname': name});
      nickname = name;
      error = null;
      return null;
    } on FirebaseFunctionsException catch (failure) {
      return failure.message ?? '닉네임을 저장하지 못했습니다.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  Future<String?> changePassword(String nextPassword, String confirm) async {
    final problem = Identity.confirmError(nextPassword, confirm);
    if (problem != null) return problem;
    final current = FirebaseAuth.instance.currentUser;
    if (current == null || !canChangePassword) {
      return '이 로그인 방식에서는 비밀번호를 바꿀 수 없습니다.';
    }
    try {
      await current.updatePassword(nextPassword);
      return null;
    } on FirebaseAuthException catch (failure) {
      if (failure.code == 'requires-recent-login') {
        return '다시 로그인한 뒤 비밀번호를 바꿔 주세요.';
      }
      return '비밀번호를 바꾸지 못했습니다.';
    }
  }

  Future<String?> deleteAccount() async {
    try {
      await Backend.call('deleteAccount', {});
      return null;
    } on FirebaseFunctionsException catch (failure) {
      return failure.message ?? '탈퇴하지 못했습니다.';
    }
  }

  Future<void> _runAuth(Future<void> Function() action, {bool phone = false}) async {
    error = null;
    busy = true;
    notifyListeners();
    try {
      await action();
    } on FirebaseAuthException catch (failure) {
      error = _authMessage(failure, phone: phone);
      busy = false;
      notifyListeners();
    }
  }

  void _show(String message) {
    error = message;
    notifyListeners();
  }

  String? _blankToNull(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  String _authMessage(FirebaseAuthException failure, {required bool phone}) {
    switch (failure.code) {
      case 'email-already-in-use':
        return phone ? '이미 가입된 번호입니다.' : '이미 가입된 이메일입니다.';
      case 'invalid-email':
        return '이메일 형식이 올바르지 않습니다.';
      case 'weak-password':
        return '비밀번호는 6자 이상이어야 합니다.';
      case 'invalid-credential':
      case 'user-not-found':
      case 'wrong-password':
        return phone ? '번호 또는 비밀번호가 올바르지 않습니다.' : '이메일 또는 비밀번호가 올바르지 않습니다.';
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        return 'Google 로그인을 취소했습니다.';
      case 'operation-not-allowed':
        return '이 로그인 방식을 아직 사용할 수 없습니다.';
      default:
        return '로그인에 실패했습니다.';
    }
  }
}
