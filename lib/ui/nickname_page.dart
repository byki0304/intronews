import 'package:flutter/material.dart';

import '../config.dart';
import '../state/session.dart';
import 'logo.dart';

class NicknamePage extends StatefulWidget {
  const NicknamePage({super.key, required this.session});

  final Session session;

  @override
  State<NicknamePage> createState() => _NicknamePageState();
}

class _NicknamePageState extends State<NicknamePage> {
  final _nickname = TextEditingController();
  String? _validation;

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = await widget.session.submitNickname(_nickname.text);
    if (!mounted) return;
    setState(() => _validation = message);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final guest = session.authProvider == 'anonymous';
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
                  const SizedBox(height: 16),
                  Text(guest ? '이번 방문에 쓸 닉네임을 만들어 주세요.' : '닉네임을 만들어 주세요.'),
                  const SizedBox(height: 8),
                  const Text('16자 이내의 문자와 숫자를 사용할 수 있습니다. 대소문자는 구분하지 않습니다.'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nickname,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(labelText: '닉네임'),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 12),
                  _LiveValidation(_validation),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: session.busy ? null : _submit,
                    child: const Text('홈으로 이동'),
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
