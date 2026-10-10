import 'package:flutter/material.dart';

import '../logic/identity.dart';
import '../state/session.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.session});

  final Session session;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _nickname = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _editingPassword = false;
  bool _withdrawArmed = false;
  String? _validation;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _nickname.text = widget.session.nickname ?? '';
  }

  @override
  void didUpdateWidget(AccountPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nickname = widget.session.nickname ?? '';
    if (_nickname.text.isEmpty && nickname.isNotEmpty) _nickname.text = nickname;
  }

  @override
  void dispose() {
    _nickname.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('마이페이지', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        Text('닉네임', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
          controller: _nickname,
          decoration: const InputDecoration(labelText: '닉네임'),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: session.busy
                ? null
                : () async {
                    final message = await session.submitNickname(_nickname.text);
                    if (!mounted) return;
                    setState(() {
                      _validation = message;
                      _notice = message == null
                          ? (session.authProvider == 'anonymous'
                              ? '이번 방문의 닉네임을 바꿨습니다.'
                              : '닉네임을 저장했습니다.')
                          : null;
                    });
                  },
            child: const Text('닉네임 수정'),
          ),
        ),
        const SizedBox(height: 20),
        Text('ID', style: Theme.of(context).textTheme.labelLarge),
        Text(session.maskedId),
        const SizedBox(height: 20),
        Text('비밀번호', style: Theme.of(context).textTheme.labelLarge),
        const Text('********'),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () => setState(() {
              _editingPassword = !_editingPassword;
              _validation = null;
            }),
            child: const Text('비밀번호 수정'),
          ),
        ),
        if (_editingPassword) ...[
          const SizedBox(height: 12),
          if (!session.canChangePassword)
            const Text('이 로그인 방식에서는 비밀번호를 바꿀 수 없습니다.')
          else ...[
            TextField(
              controller: _next,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(labelText: '새 비밀번호'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _confirm,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(labelText: '비밀번호 확인'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final local = Identity.confirmError(_next.text, _confirm.text);
                if (local != null) {
                  setState(() => _validation = local);
                  return;
                }
                final message = await session.changePassword(_next.text, _confirm.text);
                if (!mounted) return;
                setState(() {
                  _validation = message;
                  _notice = message == null ? '비밀번호를 바꿨습니다.' : null;
                  if (message == null) {
                    _editingPassword = false;
                    _next.clear();
                    _confirm.clear();
                  }
                });
              },
              child: const Text('수정 확인'),
            ),
          ],
        ],
        const SizedBox(height: 28),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _withdrawArmed ? const Color(0xFFB42318) : const Color(0xFF8A5A00),
            ),
            onPressed: session.busy
                ? null
                : () async {
                    if (!_withdrawArmed) {
                      setState(() {
                        _withdrawArmed = true;
                        _notice = '탈퇴하면 이메일, 전화번호, 비밀번호로 다시 들어올 수 없습니다.';
                        _validation = null;
                      });
                      return;
                    }
                    final message = await session.deleteAccount();
                    if (!mounted) return;
                    setState(() => _validation = message);
                  },
            child: Text(_withdrawArmed ? '탈퇴 확인' : '회원탈퇴'),
          ),
        ),
        const SizedBox(height: 12),
        _LiveValidation(_validation),
        if (_notice != null) ...[
          const SizedBox(height: 8),
          Text(_notice!),
        ],
      ],
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
