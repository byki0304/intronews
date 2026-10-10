import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../config.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final selected = <String>{};
  bool uploading = false;

  Future<void> _create(String genre) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance.collection('projects').add({
      'ownerUid': uid,
      'genre': genre,
      'pdfMode': 'single',
      'title': genre == 'news' ? '뉴스 프로젝트' : '강의 프로젝트',
      'currentStep': 1,
      'listed': false,
      'lastSavedStep': 1,
      'mainCharacterId': null,
      'mainBackgroundId': null,
      'extraCharacterIds': <String>[],
      'extraBackgroundIds': <String>[],
      'directionNote': '',
      'staleFromStep': null,
      'synopsis': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    widget.onOpen(doc.id);
  }

  Future<void> _deleteSelected() async {
    final ids = selected.toList();
    if (ids.isEmpty) return;
    setState(() => uploading = true);
    try {
      for (final id in ids) {
        await _deleteProject(id);
      }
      if (mounted) {
        setState(() => selected.removeAll(ids));
      }
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> _deleteProject(String id) async {
    final ref = FirebaseFirestore.instance.collection('projects').doc(id);
    final files = await ref.collection('files').get();
    for (final doc in files.docs) {
      await _deleteStorage(doc.data()['storagePath']?.toString());
      await doc.reference.delete();
    }
    for (final name in ['scenes', 'characters', 'music']) {
      final snap = await ref.collection(name).get();
      for (final doc in snap.docs) {
        final data = doc.data();
        await _deleteStorage(data['videoStoragePath']?.toString());
        await _deleteStorage(data['replacementPath']?.toString());
        await _deleteStorage(data['audioA']?.toString());
        await _deleteStorage(data['audioB']?.toString());
        final images = data['imagePaths'];
        if (images is List) {
          for (final item in images) {
            await _deleteStorage(item?.toString());
          }
        }
        await doc.reference.delete();
      }
    }
    await ref.delete();
  }

  Future<void> _deleteStorage(String? path) async {
    if (path == null || path.isEmpty || path.startsWith('http')) return;
    try {
      await FirebaseStorage.instance.ref(path).delete();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('무엇을 만들까요?', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('PDF의 뉴스 또는 강의 스토리를 10개 장면의 Flow 패키지로 만듭니다.'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _GenreCard(
              title: 'News',
              body: 'HS 스튜디오의 피처 스토리',
              color: const Color(AppColors.news),
              onTap: uploading ? null : () => _create('news'),
            ),
            _GenreCard(
              title: 'Lecture',
              body: '150석 강의실의 다큐멘터리 강의',
              color: const Color(AppColors.lecture),
              onTap: uploading ? null : () => _create('lecture'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        if (uid == null)
          const Text('로그인 상태가 없습니다.')
        else
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('projects')
                .where('ownerUid', isEqualTo: uid)
                .snapshots(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs.where((doc) => doc.data()['listed'] == true).toList() ?? [];
              docs.sort((a, b) {
                final left = a.data()['updatedAt'];
                final right = b.data()['updatedAt'];
                final leftMs = left is Timestamp ? left.millisecondsSinceEpoch : 0;
                final rightMs = right is Timestamp ? right.millisecondsSinceEpoch : 0;
                return rightMs.compareTo(leftMs);
              });
              final ids = docs.map((doc) => doc.id).toSet();
              selected.removeWhere((id) => !ids.contains(id));
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('프로젝트', style: Theme.of(context).textTheme.titleLarge),
                      if (docs.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        TextButton(
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.hovered)) return const Color(0xFFFF6666);
                              return null;
                            }),
                            foregroundColor: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.hovered)) return Colors.white;
                              return const Color(0xFF333333);
                            }),
                          ),
                          onPressed: uploading || selected.isEmpty ? null : _deleteSelected,
                          child: const Text('삭제'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (docs.isEmpty)
                    const Text('아직 프로젝트가 없습니다.')
                  else
                    for (var index = 0; index < docs.length; index += 1) ...[
                      if (index > 0) const SizedBox(height: 12),
                      _ProjectRow(
                        title: docs[index].data()['title']?.toString() ?? '제목 없음',
                        checked: selected.contains(docs[index].id),
                        onCheck: (value) {
                          setState(() {
                            if (value) {
                              selected.add(docs[index].id);
                            } else {
                              selected.remove(docs[index].id);
                            }
                          });
                        },
                        onOpen: () => widget.onOpen(docs[index].id),
                      ),
                    ],
                ],
              );
            },
          ),
      ],
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.title,
    required this.checked,
    required this.onCheck,
    required this.onOpen,
  });

  final String title;
  final bool checked;
  final ValueChanged<bool> onCheck;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Checkbox(
          value: checked,
          side: const BorderSide(color: Color(0xFFCCCCCC), width: 1.5),
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return const Color(0xFFFF9900);
            return Colors.white;
          }),
          checkColor: Colors.white,
          onChanged: (value) => onCheck(value == true),
        ),
        Expanded(
          child: InkWell(
            onTap: onOpen,
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF333333)),
            ),
          ),
        ),
      ],
    );
  }
}

class _GenreCard extends StatelessWidget {
  const _GenreCard({
    required this.title,
    required this.body,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String body;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(backgroundColor: color, radius: 8),
                const SizedBox(height: 12),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(body),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
