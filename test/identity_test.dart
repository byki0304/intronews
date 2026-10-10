import 'package:flutter_test/flutter_test.dart';
import 'package:intronews/logic/identity.dart';

void main() {
  test('phone login ignores dashes and a leading zero', () {
    expect(Identity.canonicalPhone('+82', '10-5279-9244'), '821052799244');
    expect(Identity.canonicalPhone('82', '01052799244'), '821052799244');
    expect(Identity.canonicalPhone('+82', '82 10-5279-9244'), '821052799244');
    expect(Identity.authEmailForPhone('+82', '10-5279-9244'), 'p821052799244@phone.intronews.app');
  });

  test('nickname allows letters and numbers within 16 characters', () {
    expect(Identity.nicknameError('뉴스12'), isNull);
    expect(Identity.nicknameError('NewsRoom'), isNull);
    expect(Identity.nicknameError('a' * 16), isNull);
    expect(Identity.nicknameError('a' * 17), isNotNull);
    expect(Identity.nicknameError('has space'), isNotNull);
    expect(Identity.nicknameError(''), isNotNull);
  });

  test('account ids are masked', () {
    expect(Identity.maskEmail('nfriend02@naver.com'), 'n*******2@naver.com');
    expect(Identity.maskPhone('821052799244'), '+82 10-****-9244');
    expect(Identity.maskAccount(email: 'byki@daum.net'), 'b**i@daum.net');
  });
}
