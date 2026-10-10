import 'package:flutter/material.dart';

import '../config.dart';
import '../state/session.dart';
import 'logo.dart';

enum _AuthView { gate, signupChoice, signupEmail, signupPhone, loginChoice, loginEmail, loginPhone }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.session});

  final Session session;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  _AuthView _view = _AuthView.gate;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _country = TextEditingController(text: '+82');
  final _phone = TextEditingController();
  String? _validation;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _country.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _open(_AuthView view) {
    setState(() {
      _view = view;
      _validation = null;
      widget.session.error = null;
    });
  }

  void _setValidation(String? message) {
    setState(() => _validation = message);
  }

  @override
  Widget build(BuildContext context) {
    if (_view == _AuthView.gate) return _gate();
    return Scaffold(
      backgroundColor: const Color(AppColors.navy),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _form(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _gate() {
    final session = widget.session;
    return Scaffold(
      backgroundColor: const Color(AppColors.navy),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const IntroNewsLogo(onDark: true, markSize: 72),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: 220,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(AppColors.news),
                            foregroundColor: const Color(AppColors.navy),
                          ),
                          onPressed: session.busy ? null : () => _open(_AuthView.loginChoice),
                          child: const Text('로그인'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 220,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white),
                          ),
                          onPressed: session.busy ? null : () => _open(_AuthView.signupChoice),
                          child: const Text('신규회원'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: session.busy ? null : session.startWithoutLogin,
                        child: const Text('로그인 없이 사용', style: TextStyle(color: Colors.white70)),
                      ),
                    ],
                  ),
                ),
              ),
              const Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 320,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '환영합니다.',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '뉴스나 강의 PDF로 10개 장면의 Flow 프롬프트를 만듭니다.',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: Colors.white70),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '사용법: 로그인하거나 가입한 뒤 자료를 올리고 단계를 따라가세요. 로그인 없이 쓸 때 닉네임은 이번 방문에만 유지됩니다.',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _form() {
    final session = widget.session;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: session.busy ? null : () => _open(_AuthView.gate), child: const Text('처음으로')),
        ),
        const IntroNewsLogo(markSize: 40),
        const SizedBox(height: 16),
        ..._fields(session),
        const SizedBox(height: 12),
        _LiveValidation(_validation ?? session.error),
      ],
    );
  }

  List<Widget> _fields(Session session) {
    switch (_view) {
      case _AuthView.signupChoice:
        return [
          const Text('가입 방법을 고르세요.'),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => _open(_AuthView.signupEmail), child: const Text('이메일 가입')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => _open(_AuthView.signupPhone), child: const Text('휴대폰 가입')),
        ];
      case _AuthView.loginChoice:
        return [
          const Text('로그인 방법을 고르세요.'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: session.busy ? null : session.signInWithGoogle,
            child: const Text('Google로 로그인'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => _open(_AuthView.loginEmail), child: const Text('이메일 로그인')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => _open(_AuthView.loginPhone), child: const Text('휴대폰 로그인')),
        ];
      case _AuthView.signupEmail:
        return [
          const Text('이메일 가입'),
          const SizedBox(height: 12),
          _emailField(),
          const SizedBox(height: 12),
          _secretField(_password, '비밀번호'),
          const SizedBox(height: 12),
          _secretField(_confirm, '비밀번호 확인', onSubmit: _submitEmailSignup),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: session.busy ? null : _submitEmailSignup,
            child: const Text('가입하기'),
          ),
        ];
      case _AuthView.signupPhone:
        return [
          const Text('휴대폰 가입'),
          const SizedBox(height: 12),
          _phoneFields(),
          const SizedBox(height: 12),
          _secretField(_password, '비밀번호'),
          const SizedBox(height: 12),
          _secretField(_confirm, '비밀번호 확인', onSubmit: _submitPhoneSignup),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: session.busy ? null : _submitPhoneSignup,
            child: const Text('가입하기'),
          ),
        ];
      case _AuthView.loginEmail:
        return [
          const Text('이메일 로그인'),
          const SizedBox(height: 12),
          _emailField(),
          const SizedBox(height: 12),
          _secretField(_password, '비밀번호', onSubmit: _submitEmailLogin),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: session.busy ? null : _submitEmailLogin,
            child: const Text('로그인'),
          ),
        ];
      case _AuthView.loginPhone:
        return [
          const Text('휴대폰 로그인'),
          const SizedBox(height: 12),
          _phoneFields(),
          const SizedBox(height: 12),
          _secretField(_password, '비밀번호', onSubmit: _submitPhoneLogin),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: session.busy ? null : _submitPhoneLogin,
            child: const Text('로그인'),
          ),
        ];
      case _AuthView.gate:
        return const [];
    }
  }

  Widget _emailField() {
    return TextField(
      controller: _email,
      keyboardType: TextInputType.emailAddress,
      decoration: const InputDecoration(
        labelText: '이메일',
        hintText: '*****@*********.com',
      ),
    );
  }

  Widget _phoneFields() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: TextField(
            controller: _country,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: '국가 코드'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: '휴대폰 번호'),
          ),
        ),
      ],
    );
  }

  Widget _secretField(TextEditingController controller, String label, {VoidCallback? onSubmit}) {
    return TextField(
      controller: controller,
      obscureText: true,
      enableSuggestions: false,
      autocorrect: false,
      decoration: InputDecoration(labelText: label),
      onSubmitted: onSubmit == null ? null : (_) => onSubmit(),
    );
  }

  void _submitEmailSignup() {
    _setValidation(null);
    widget.session.signUpWithEmail(_email.text, _password.text, _confirm.text);
  }

  void _submitPhoneSignup() {
    _setValidation(null);
    widget.session.signUpWithPhone(_country.text, _phone.text, _password.text, _confirm.text);
  }

  void _submitEmailLogin() {
    _setValidation(null);
    widget.session.signInWithEmail(_email.text, _password.text);
  }

  void _submitPhoneLogin() {
    _setValidation(null);
    widget.session.signInWithPhone(_country.text, _phone.text, _password.text);
  }
}

class _LiveValidation extends StatelessWidget {
  const _LiveValidation(this.message);

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Text(
        message ?? '',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}
