import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  Future<void> _upload(String kind) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final picked = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = picked?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    final doc = FirebaseFirestore.instance.collection('assetLibrary').doc();
    final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : 'png';
    final path = 'users/${user.uid}/library/${doc.id}.$ext';
    await FirebaseStorage.instance.ref(path).putData(bytes);
    await doc.set({
      'ownerUid': user.uid,
      'kind': kind,
      'storagePath': path,
      'name': file.name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final path = item['storagePath']?.toString();
    if (path != null) {
      await FirebaseStorage.instance.ref(path).delete();
    }
    await FirebaseFirestore.instance.collection('assetLibrary').doc(item['id'].toString()).delete();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Center(child: Text('로그인 상태가 없습니다.'));
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('assetLibrary')
          .where('ownerUid', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        final items = snapshot.data?.docs
                .map((doc) => {'id': doc.id, ...doc.data()})
                .toList() ??
            [];
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('이미지 라이브러리', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('메인 캐릭터와 메인 배경은 여기서 고르거나, 자료 준비 단계에서 올릴 수 있습니다. 앱이 메인 이미지를 만들지는 않습니다.'),
            const SizedBox(height: 16),
            _Section(
              title: '캐릭터',
              items: items.where((item) => item['kind'] == 'character').toList(),
              onUpload: () => _upload('character'),
              onDelete: _delete,
            ),
            const SizedBox(height: 24),
            _Section(
              title: '배경',
              items: items.where((item) => item['kind'] == 'background').toList(),
              onUpload: () => _upload('background'),
              onDelete: _delete,
            ),
          ],
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.items,
    required this.onUpload,
    required this.onDelete,
  });

  final String title;
  final List<Map<String, dynamic>> items;
  final VoidCallback onUpload;
  final ValueChanged<Map<String, dynamic>> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            OutlinedButton(
              style: const ButtonStyle(
                backgroundColor: WidgetStateProperty.fromMap({
                  WidgetState.hovered: Color(0xFFF0F0F0),
                }),
              ),
              onPressed: onUpload,
              child: const Text('업로드'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Text('아직 없습니다.')
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final item in items)
                SizedBox(
                  width: 160,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Thumb(path: item['storagePath']?.toString() ?? ''),
                      const SizedBox(height: 4),
                      Text(item['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                      TextButton(onPressed: () => onDelete(item), child: const Text('삭제')),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) return const SizedBox(height: 90);
    return FutureBuilder<String>(
      future: FirebaseStorage.instance.ref(path).getDownloadURL(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(height: 90, child: Center(child: CircularProgressIndicator()));
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(snapshot.data!, height: 90, width: 160, fit: BoxFit.cover),
        );
      },
    );
  }
}
