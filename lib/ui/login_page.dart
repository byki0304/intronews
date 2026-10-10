import 'package:flutter/material.dart';

import '../config.dart';
import '../state/session.dart';
import 'logo.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.session});

  final Session session;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Scaffold(
      backgroundColor: const Color(AppColors.navy),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const IntroNewsLogo(markSize: 48),
                  const SizedBox(height: 12),
                  const Text('허용된 이메일 계정으로 들어오거나, 로그인 없이 작업을 시작합니다.'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: '이메일'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: '비밀번호'),
                    onSubmitted: (_) => session.signIn(_email.text, _password.text),
                  ),
                  if (session.error != null) ...[
                    const SizedBox(height: 12),
                    Text(session.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: session.busy ? null : () => session.signIn(_email.text, _password.text),
                    child: const Text('로그인'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: session.busy ? null : session.startAnonymous,
                    child: const Text('로그인 없이 시작'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
