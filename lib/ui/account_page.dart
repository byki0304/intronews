import 'package:flutter/material.dart';

import '../state/session.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.session});

  final Session session;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  String? _message;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final email = (session.email == null || session.email!.isEmpty) ? '없음' : session.email!;
    final role = session.role == 'admin' ? '관리자' : '멤버';
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('마이페이지', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        Text('이메일', style: Theme.of(context).textTheme.labelLarge),
        Text(email),
        const SizedBox(height: 12),
        Text('역할', style: Theme.of(context).textTheme.labelLarge),
        Text(role),
        const SizedBox(height: 20),
        Text('비밀번호 변경', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (session.authProvider != 'password')
          const Text('이메일 계정에서만 비밀번호를 바꿀 수 있습니다.')
        else ...[
          TextField(
            controller: _current,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '현재 비밀번호'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _next,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '새 비밀번호'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              final message = await session.changePassword(_current.text, _next.text);
              if (!mounted) return;
              setState(() => _message = message ?? '비밀번호를 바꿨습니다.');
              if (message == null) {
                _current.clear();
                _next.clear();
              }
            },
            child: const Text('비밀번호 변경'),
          ),
        ],
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!),
        ],
      ],
    );
  }
}
