class Identity {
  static const phoneDomain = 'phone.intronews.app';

  static String? emailError(String value) {
    final text = value.trim();
    if (text.isEmpty) return '이메일을 입력해 주세요.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
      return '이메일 형식이 올바르지 않습니다.';
    }
    return null;
  }

  static String? passwordError(String value) {
    if (value.isEmpty) return '비밀번호를 입력해 주세요.';
    if (value.length < 6) return '비밀번호는 6자 이상이어야 합니다.';
    return null;
  }

  static String? confirmError(String password, String confirm) {
    final first = passwordError(password);
    if (first != null) return first;
    if (confirm.isEmpty) return '비밀번호 확인을 입력해 주세요.';
    if (password != confirm) return '비밀번호가 서로 다릅니다.';
    return null;
  }

  static String? phoneError(String country, String national) {
    final code = country.replaceAll(RegExp(r'\D'), '');
    final number = national.replaceAll(RegExp(r'\D'), '');
    if (code.isEmpty) return '국가 코드를 입력해 주세요.';
    if (number.isEmpty) return '휴대폰 번호를 입력해 주세요.';
    final digits = canonicalPhone(country, national);
    if (digits.length < 10 || digits.length > 15) return '휴대폰 번호를 확인해 주세요.';
    return null;
  }

  static String canonicalPhone(String country, String national) {
    var code = country.replaceAll(RegExp(r'\D'), '');
    var number = national.replaceAll(RegExp(r'\D'), '');
    if (code.isEmpty) code = '82';
    if (number.startsWith('0')) number = number.substring(1);
    if (number.startsWith(code) && number.length > code.length + 7) return number;
    return '$code$number';
  }

  static String authEmailForPhone(String country, String national) {
    return 'p${canonicalPhone(country, national)}@$phoneDomain';
  }

  static bool isPhoneAuthEmail(String? email) {
    if (email == null) return false;
    return email.toLowerCase().endsWith('@$phoneDomain');
  }

  static String? nicknameError(String value) {
    final name = value.trim();
    if (name.isEmpty) return '닉네임을 입력해 주세요.';
    final pattern = RegExp(r'^[\p{L}\p{N}]{1,16}$', unicode: true);
    if (!pattern.hasMatch(name)) {
      return '닉네임은 16자 이내의 문자와 숫자만 사용할 수 있습니다.';
    }
    return null;
  }

  static String maskEmail(String email) {
    final parts = email.trim().split('@');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) return '****';
    final local = parts[0];
    if (local.length == 1) return '*@${parts[1]}';
    final hidden = '*' * (local.length - 2);
    return '${local[0]}$hidden${local[local.length - 1]}@${parts[1]}';
  }

  static String maskPhone(String digits) {
    final clean = digits.replaceAll(RegExp(r'\D'), '');
    if (clean.length < 8) return '****';
    final last4 = clean.substring(clean.length - 4);
    final rest = clean.startsWith('82') ? clean.substring(2) : clean;
    final head = rest.length >= 2 ? rest.substring(0, 2) : rest;
    return '+82 $head-****-$last4';
  }

  static String maskAccount({String? email, String? phone}) {
    if (phone != null && phone.isNotEmpty) return maskPhone(phone);
    if (email != null && email.isNotEmpty && !isPhoneAuthEmail(email)) return maskEmail(email);
    return '비로그인';
  }
}
