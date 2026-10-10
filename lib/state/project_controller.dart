import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';

import '../backend.dart';
import '../config.dart';
import '../logic/step_gate.dart';
import '../platform/save_file.dart';

const cardFieldKeys = [
  'title',
  'description',
  'characters',
  'region',
  'place',
  'background',
  'era',
  'year',
  'action',
  'dialogue',
  'narration',
  'cameraMove',
  'shotChange',
  'mood',
  'sfx',
  'bgm',
  'generationNotes',
  'visualStorytellingGoal',
  'emotionalTone',
  'scenePurpose',
  'directorIntent',
  'timeOfDay',
  'weather',
  'lighting',
  'colorTone',
  'visualFocus',
  'transitionToNext',
];

class ProjectController extends ChangeNotifier {
  ProjectController(this.projectId);

  final String projectId;
  final _subs = <StreamSubscription<dynamic>>[];

  Map<String, dynamic>? project;
  List<Map<String, dynamic>> files = [];
  List<Map<String, dynamic>> scenes = [];
  List<Map<String, dynamic>> roles = [];
  Map<String, dynamic>? music;
  List<Map<String, dynamic>> library = [];

  bool loading = true;
  bool busy = false;
  String? error;
  int viewingStep = 1;
  int epoch = 0;
  bool dirty = false;
  bool _opened = false;
  Map<String, dynamic> draft = {};
  String _baseline = '';
  List<Map<String, dynamic>>? pendingRoles;
  final Set<String> pendingKeep = {};

  DocumentReference<Map<String, dynamic>> get ref =>
      FirebaseFirestore.instance.collection('projects').doc(projectId);

  String get uid => FirebaseAuth.instance.currentUser!.uid;
  int get currentStep => (project?['currentStep'] as num?)?.toInt() ?? 1;
  int? get staleFromStep => (project?['staleFromStep'] as num?)?.toInt();
  String get genre => project?['genre']?.toString() ?? 'news';

  bool get canSave => StepGate.canSave(
        busy: busy,
        requirementsMet: requirementsMet(viewingStep),
      );

  bool get canGoNext => StepGate.canGoNext(
        step: viewingStep,
        busy: busy,
        requirementsMet: requirementsMet(viewingStep),
        staleFromStep: staleFromStep,
      );

  void listen() {
    _subs.add(ref.snapshots().listen((snap) {
      project = snap.data();
      if (!_opened && project != null) {
        final saved = (project?['lastSavedStep'] as num?)?.toInt();
        final reached = currentStep.clamp(1, 8);
        viewingStep = (saved ?? reached).clamp(1, reached);
        _opened = true;
      }
      _maybeCapture();
      loading = false;
      notifyListeners();
    }));
    _subs.add(ref.collection('files').snapshots().listen((snap) {
      files = snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList()
        ..sort((a, b) => ((a['order'] as num?) ?? 0).compareTo((b['order'] as num?) ?? 0));
      _mergeFiles();
      notifyListeners();
    }));
    _subs.add(ref.collection('scenes').snapshots().listen((snap) {
      scenes = snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      _maybeCapture();
      notifyListeners();
    }));
    _subs.add(ref.collection('characters').snapshots().listen((snap) {
      roles = snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList()
        ..sort((a, b) => a['id'].toString().compareTo(b['id'].toString()));
      _maybeCapture();
      notifyListeners();
    }));
    _subs.add(ref.collection('music').doc('score').snapshots().listen((snap) {
      music = snap.data();
      _maybeCapture();
      notifyListeners();
    }));
    _subs.add(
      FirebaseFirestore.instance
          .collection('assetLibrary')
          .where('ownerUid', isEqualTo: uid)
          .snapshots()
          .listen((snap) {
        library = snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
        notifyListeners();
      }),
    );
  }

  Map<String, dynamic> scene(String id) {
    for (final item in scenes) {
      if (item['id'] == id) return item;
    }
    return {'id': id, 'status': 'empty'};
  }

  List<Map<String, dynamic>> byKind(String kind) {
    final items = library.where((item) => item['kind'] == kind).toList();
    items.sort((a, b) {
      final at = a['createdAt'];
      final bt = b['createdAt'];
      if (at is Timestamp && bt is Timestamp) return at.compareTo(bt);
      return (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString());
    });
    return items;
  }

  bool requirementsMet(int step) {
    switch (step) {
      case 1:
        final mode = (draft['pdfMode'] ?? project?['pdfMode'] ?? 'single').toString();
        final ready = _filled(draft['mainCharacterId']) && _filled(draft['mainBackgroundId']);
        if (!ready) return false;
        final selected = _selectedFileIds().length;
        if (mode == 'single') return selected == 1;
        return selected >= 1 && selected <= 10;
      case 2:
        return _filled(draft['synopsis']) && AppConfig.sceneIds.every(_outlineReady);
      case 3:
        return AppConfig.sceneIds.every(_cardReady);
      case 4:
        if (roles.isEmpty) return currentStep >= 4;
        return roles.every((role) => !wantsGeneration(role) || _roleChosen(role));
      case 5:
        return ['02', '03', '04', '05', '06', '07', '08', '09'].every(_promptReady);
      case 6:
        return _promptReady('01');
      case 7:
        return _promptReady('10');
      default:
        return true;
    }
  }

  void edit(void Function() change) {
    change();
    dirty = jsonEncode(draft) != _baseline;
    notifyListeners();
  }

  void setField(String key, Object? value) {
    edit(() => draft[key] = value);
  }

  void setMain(String kind, String id) {
    edit(() {
      final mainKey = kind == 'character' ? 'mainCharacterId' : 'mainBackgroundId';
      final extraKey = kind == 'character' ? 'extraCharacterIds' : 'extraBackgroundIds';
      final extras = _stringList(draft[extraKey]);
      final previous = draft[mainKey]?.toString();
      if (previous != null && previous.isNotEmpty && previous != id && !extras.contains(previous)) {
        extras.add(previous);
      }
      extras.remove(id);
      draft[mainKey] = id;
      draft[extraKey] = extras;
    });
  }

  void toggleIncluded(String kind, String id, bool selected) {
    edit(() {
      final mainKey = kind == 'character' ? 'mainCharacterId' : 'mainBackgroundId';
      final extraKey = kind == 'character' ? 'extraCharacterIds' : 'extraBackgroundIds';
      final extras = _stringList(draft[extraKey]);
      final main = draft[mainKey]?.toString();
      if (selected) {
        if (!_filled(main)) {
          draft[mainKey] = id;
        } else if (main != id && !extras.contains(id)) {
          extras.add(id);
          draft[extraKey] = extras;
        }
        return;
      }
      extras.remove(id);
      if (main == id) {
        draft[mainKey] = extras.isEmpty ? null : extras.removeAt(0);
      }
      draft[extraKey] = extras;
    });
  }

  bool isIncluded(String kind, String id) {
    final mainKey = kind == 'character' ? 'mainCharacterId' : 'mainBackgroundId';
    final extraKey = kind == 'character' ? 'extraCharacterIds' : 'extraBackgroundIds';
    if (draft[mainKey]?.toString() == id) return true;
    return _stringList(draft[extraKey]).contains(id);
  }

  List<String> includedIds(String kind) {
    final mainKey = kind == 'character' ? 'mainCharacterId' : 'mainBackgroundId';
    final extraKey = kind == 'character' ? 'extraCharacterIds' : 'extraBackgroundIds';
    final ids = <String>[];
    final main = draft[mainKey]?.toString();
    if (_filled(main)) ids.add(main!);
    for (final id in _stringList(draft[extraKey])) {
      if (!ids.contains(id)) ids.add(id);
    }
    return ids;
  }

  void toggleFileIncluded(String id, bool selected) {
    edit(() {
      final list = _stringList(draft['selectedFileIds']);
      if (selected) {
        if (!list.contains(id)) list.add(id);
      } else {
        list.remove(id);
      }
      draft['selectedFileIds'] = list;
    });
  }

  bool isFileIncluded(String id) => _selectedFileIds().contains(id);

  void toggleExtra(String kind, String id, bool selected) {
    edit(() {
      final key = kind == 'character' ? 'extraCharacterIds' : 'extraBackgroundIds';
      final list = _stringList(draft[key]);
      if (selected) {
        if (!list.contains(id)) list.add(id);
      } else {
        list.remove(id);
      }
      draft[key] = list;
    });
  }

  void moveFile(String id, int delta) {
    edit(() {
      final order = _stringList(draft['fileOrder']);
      final index = order.indexOf(id);
      final next = index + delta;
      if (index < 0 || next < 0 || next >= order.length) return;
      final item = order.removeAt(index);
      order.insert(next, item);
      draft['fileOrder'] = order;
    });
  }

  void setOutline(String id, String key, String value) {
    edit(() {
      final outlines = Map<String, dynamic>.from(draft['outlines'] as Map? ?? {});
      final item = Map<String, dynamic>.from(outlines[id] as Map? ?? {});
      item[key] = value;
      outlines[id] = item;
      draft['outlines'] = outlines;
    });
  }

  void setCard(String id, String key, String value) {
    edit(() {
      final cards = Map<String, dynamic>.from(draft['cards'] as Map? ?? {});
      final item = Map<String, dynamic>.from(cards[id] as Map? ?? {});
      item[key] = value;
      cards[id] = item;
      draft['cards'] = cards;
    });
  }

  void setPrompt(String id, String value) {
    edit(() {
      final prompts = Map<String, dynamic>.from(draft['prompts'] as Map? ?? {});
      prompts[id] = value;
      draft['prompts'] = prompts;
    });
  }

  void selectRole(String roleId, int index) {
    edit(() => _setRolePick(roleId, index));
  }

  void clearRolePick(String roleId) {
    edit(() => _setRolePick(roleId, -2));
  }

  void _setRolePick(String roleId, int index) {
    final all = Map<String, dynamic>.from(draft['roles'] as Map? ?? {});
    final current = Map<String, dynamic>.from(all[roleId] as Map? ?? {});
    all[roleId] = {
      'selectedIndex': index,
      'replacementPath': current['replacementPath'],
      'generate': current.containsKey('generate') ? current['generate'] == true : _storedGenerate(roleId),
    };
    draft['roles'] = all;
  }

  void toggleGenerate(String roleId, bool selected) {
    edit(() {
      final all = Map<String, dynamic>.from(draft['roles'] as Map? ?? {});
      final current = Map<String, dynamic>.from(all[roleId] as Map? ?? {});
      if (selected) {
        final count = roles.where((role) => role['id'].toString() != roleId && wantsGeneration(role)).length;
        if (count >= AppConfig.maxGeneratedCharacters) return;
      }
      all[roleId] = {
        'selectedIndex': selected ? current['selectedIndex'] : -2,
        'replacementPath': current['replacementPath'],
        'generate': selected,
      };
      draft['roles'] = all;
    });
  }

  int get generatePickCount => roles.where(wantsGeneration).length;

  bool wantsGeneration(Map<String, dynamic> role) {
    final drafts = draft['roles'];
    final id = role['id'].toString();
    if (drafts is Map && drafts[id] is Map && (drafts[id] as Map).containsKey('generate')) {
      return drafts[id]['generate'] == true;
    }
    return _storedGenerate(id);
  }

  bool _storedGenerate(String roleId) {
    for (final role in roles) {
      if (role['id'].toString() != roleId) continue;
      if (role['generate'] == true) return true;
      if (role['generate'] == false) return false;
      final paths = role['imagePaths'];
      return paths is List && paths.isNotEmpty;
    }
    return false;
  }

  Future<void> saveCurrent() async {
    if (!canSave) return;
    final wasDirty = dirty;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await _persist(viewingStep);
      await _publishListing(viewingStep);
      if (wasDirty) await _writeStale(viewingStep);
      dirty = false;
      _baseline = jsonEncode(draft);
      epoch += 1;
    } catch (caught) {
      error = '저장하지 못했습니다.';
      debugPrint('save failed: $caught');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> goNext() async {
    if (!canGoNext) return;
    final step = viewingStep;
    await saveCurrent();
    if (error != null) return;
    final regenerate = StepGate.regeneratesOnNext(
      step: step,
      currentStep: currentStep,
      staleFromStep: staleFromStep,
    );
    if (!regenerate) {
      viewingStep = step + 1;
      await _publishListing(viewingStep);
      notifyListeners();
      return;
    }
    await _runStep(step, {});
  }

  Future<void> confirmPendingRoles() async {
    final chosen = (pendingRoles ?? [])
        .where((role) => pendingKeep.contains(role['id']?.toString()))
        .map((role) => {
              'name': role['name'],
              'prompt': role['prompt'],
              'sceneIds': role['sceneIds'] ?? [],
              'members': role['members'] ?? [role['name']],
              'grouped': role['grouped'] == true,
              'noCharacter': false,
            })
        .toList();
    if (chosen.isEmpty || chosen.length > AppConfig.maxProposedCharacters) return;
    await _runStep(3, {'selectedRoles': chosen});
    if (error == null) pendingRoles = null;
  }

  void togglePending(String id, bool selected) {
    if (selected) {
      if (pendingKeep.length >= AppConfig.maxProposedCharacters) return;
      pendingKeep.add(id);
    } else {
      pendingKeep.remove(id);
    }
    notifyListeners();
  }

  Future<void> addPdfs() async {
    final multi = (draft['pdfMode'] ?? project?['pdfMode']) == 'multi';
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
      allowMultiple: multi,
    );
    if (picked == null) return;
    final incoming = <({String name, Uint8List bytes})>[];
    for (final file in picked.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      incoming.add((name: file.name, bytes: bytes));
    }
    await addPdfPayloads(incoming);
  }

  Future<void> addPdfPayloads(List<({String name, Uint8List bytes})> incoming) async {
    final pdfs = incoming.where((file) => file.name.toLowerCase().endsWith('.pdf') && file.bytes.isNotEmpty).toList();
    if (pdfs.isEmpty) return;
    final multi = (draft['pdfMode'] ?? project?['pdfMode']) == 'multi';
    if (!multi && (files.length + pdfs.length) > 1) {
      error = 'PDF 1개 모드엝서는 파일을 하나만 올릴 수 있습니다.';
      notifyListeners();
      return;
    }
    if (files.length + pdfs.length > 10) {
      error = 'PDF는 최대 10개입니다.';
      notifyListeners();
      return;
    }
    busy = true;
    notifyListeners();
    try {
      var order = files.length;
      for (final file in pdfs) {
        final doc = ref.collection('files').doc();
        final path = 'users/$uid/projects/$projectId/pdf/${doc.id}.pdf';
        await FirebaseStorage.instance.ref(path).putData(
              file.bytes,
              SettableMetadata(contentType: 'application/pdf'),
            );
        await doc.set({
          'name': file.name,
          'storagePath': path,
          'order': order,
        });
        order += 1;
      }
      await _writeStale(1);
      error = null;
    } catch (caught) {
      error = 'PDF를 저장하지 못했습니다.';
      debugPrint('pdf upload failed: $caught');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> deleteFile(String id) async {
    final file = files.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['id'] == id,
          orElse: () => null,
        );
    if (file == null) return;
    await FirebaseStorage.instance.ref(file['storagePath'].toString()).delete();
    await ref.collection('files').doc(id).delete();
    await _writeStale(1);
  }

  Future<void> deleteFiles(List<String> ids) async {
    if (ids.isEmpty) return;
    for (final id in ids) {
      await deleteFile(id);
    }
  }

  Future<void> deleteAssets(String kind, List<String> ids) async {
    if (ids.isEmpty) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      for (final id in ids) {
        Map<String, dynamic>? item;
        for (final entry in library) {
          if (entry['id'] == id) item = entry;
        }
        if (item == null) continue;
        final path = item['storagePath']?.toString();
        if (path != null && path.isNotEmpty) {
          await FirebaseStorage.instance.ref(path).delete();
        }
        await FirebaseFirestore.instance.collection('assetLibrary').doc(id).delete();
      }
      final mainKey = kind == 'character' ? 'mainCharacterId' : 'mainBackgroundId';
      final extraKey = kind == 'character' ? 'extraCharacterIds' : 'extraBackgroundIds';
      final remaining = byKind(kind).where((item) => !ids.contains(item['id'].toString())).toList();
      final currentMain = draft[mainKey]?.toString();
      final nextMain = ids.contains(currentMain)
          ? (remaining.isEmpty ? null : remaining.first['id'].toString())
          : currentMain;
      final nextExtras = _stringList(draft[extraKey]).where((id) => !ids.contains(id)).toList();
      draft[mainKey] = nextMain;
      draft[extraKey] = nextExtras;
      await ref.update({
        mainKey: nextMain,
        extraKey: nextExtras,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      project = {...?project, mainKey: nextMain, extraKey: nextExtras};
      if (_baseline.isNotEmpty) {
        final baseline = Map<String, dynamic>.from(jsonDecode(_baseline) as Map);
        baseline[mainKey] = nextMain;
        baseline[extraKey] = nextExtras;
        _baseline = jsonEncode(baseline);
      }
      dirty = jsonEncode(draft) != _baseline;
      await _writeStale(1);
    } catch (caught) {
      error = '파일을 삭제하지 못했습니다.';
      debugPrint('asset delete failed: $caught');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<String?> uploadAsset(String kind) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = picked?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return null;
    final doc = FirebaseFirestore.instance.collection('assetLibrary').doc();
    final ext = _ext(file.name, 'png');
    final path = 'users/$uid/library/${doc.id}.$ext';
    await FirebaseStorage.instance.ref(path).putData(bytes, SettableMetadata(contentType: _mime(ext)));
    await doc.set({
      'ownerUid': uid,
      'kind': kind,
      'storagePath': path,
      'name': file.name,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> generateCheckedRoles() async {
    final ids = roles.where(wantsGeneration).map((role) => role['id'].toString()).toList();
    if (ids.isEmpty || ids.length > AppConfig.maxGeneratedCharacters) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await Backend.call('generateSelectedCharacters', {
        'projectId': projectId,
        'roleIds': ids,
      });
    } on FirebaseFunctionsException catch (caught) {
      error = caught.message ?? '캐릭터를 만들지 못했습니다. 다시 실행해 주세요.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void downloadRolePrompt(Map<String, dynamic> role) {
    final name = (role['name']?.toString().trim().isNotEmpty ?? false) ? role['name'].toString().trim() : 'character';
    final text = role['prompt']?.toString() ?? '';
    saveBytes('$name-prompt.txt', utf8.encode(text), 'text/plain;charset=utf-8');
  }

  Future<void> regenerateRole(String roleId) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await Backend.call('regenerateRoleImages', {
        'projectId': projectId,
        'roleId': roleId,
      });
      edit(() {
        final all = Map<String, dynamic>.from(draft['roles'] as Map? ?? {});
        all[roleId] = {
          'selectedIndex': null,
          'replacementPath': null,
          'generate': true,
        };
        draft['roles'] = all;
      });
    } on FirebaseFunctionsException catch (caught) {
      error = caught.message ?? '이미지를 다시 만들지 못했습니다.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> replaceRoleImage(String roleId) async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = picked?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    final ext = _ext(file.name, 'png');
    final path = 'users/$uid/projects/$projectId/characters/$roleId/replacement.$ext';
    await FirebaseStorage.instance.ref(path).putData(bytes, SettableMetadata(contentType: _mime(ext)));
    edit(() {
      final all = Map<String, dynamic>.from(draft['roles'] as Map? ?? {});
      final current = Map<String, dynamic>.from(all[roleId] as Map? ?? {});
      final already = current.containsKey('generate') ? current['generate'] == true : _storedGenerate(roleId);
      var generate = already;
      if (!generate) {
        final count = roles.where((role) => role['id'].toString() != roleId && wantsGeneration(role)).length;
        if (count < AppConfig.maxGeneratedCharacters) generate = true;
      }
      all[roleId] = {
        'selectedIndex': -1,
        'replacementPath': path,
        'generate': generate,
      };
      draft['roles'] = all;
    });
  }

  Future<void> uploadSceneVideo(String sceneId) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'webm'],
      withData: true,
    );
    final file = picked?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    busy = true;
    notifyListeners();
    try {
      final ext = _ext(file.name, 'mp4');
      final path = 'users/$uid/projects/$projectId/videos/$sceneId.$ext';
      await FirebaseStorage.instance.ref(path).putData(bytes, SettableMetadata(contentType: _mime(ext)));
      await ref.collection('scenes').doc(sceneId).set({
        'videoStoragePath': path,
        'status': 'video',
      }, SetOptions(merge: true));
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> uploadMusic(String slot) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'wav', 'm4a'],
      withData: true,
    );
    final file = picked?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    final ext = _ext(file.name, 'mp3');
    final path = 'users/$uid/projects/$projectId/music/$slot.$ext';
    await FirebaseStorage.instance.ref(path).putData(bytes, SettableMetadata(contentType: _mime(ext)));
    await ref.collection('music').doc('score').set({
      slot == 'a' ? 'audioA' : 'audioB': path,
    }, SetOptions(merge: true));
  }

  Future<void> downloadPath(String path, String filename) async {
    final bytes = await FirebaseStorage.instance.ref(path).getData(100 * 1024 * 1024);
    if (bytes == null) {
      error = '파일을 내려받지 못했습니다.';
      notifyListeners();
      return;
    }
    saveBytes(filename, bytes, _mime(_ext(filename, 'bin')));
  }

  Future<void> downloadPackage() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final archive = Archive();
      final packedCharacters = <String>{};
      final packedNames = <String>{};
      final notes = StringBuffer()
        ..writeln('IntroNews Premiere 편집 메모')
        ..writeln('장면 순서: 01 오프닝, 02-09 본편, 10 흴로징')
        ..writeln('객 장면은 16:9, 8초입니다. 10장면을 이어 붙이면 마스터는 약 80초입니다.')
        ..writeln('BGM은 120초입니다. Premiere엝서 옝생 길이엝 맞게 잝르세요.')
        ..writeln('장면 연결은 객 장면의 Continuity Hint를 따릅니다.')
        ..writeln('장르: $genre');
      _addText(archive, 'edit_notes.txt', notes.toString());
      for (final id in AppConfig.sceneIds) {
        final item = scene(id);
        _addText(archive, 'scenes/$id/prompt.txt', item['flowPrompt']?.toString() ?? '');
        _addText(archive, 'scenes/$id/continuity.txt', item['continuityHint']?.toString() ?? '');
        _addText(
          archive,
          'scenes/$id/source_pdfs.txt',
          ((item['sourcePdfNames'] as List?) ?? []).join('\n'),
        );
        final video = item['videoStoragePath']?.toString();
        if (video != null && video.isNotEmpty) {
          await _addStorage(archive, 'scenes/$id/video${_dotExt(video)}', video);
        }
        final refs = (item['referenceAssetIds'] as List?) ?? [];
        for (var index = 0; index < refs.length; index += 1) {
          final path = refs[index].toString();
          await _addStorage(archive, 'scenes/$id/reference_$index${_dotExt(path)}', path);
        }
      }
      for (final role in roles) {
        if (!_includeCharacter(role)) continue;
        final path = _selectedRoleStorage(role);
        if (path == null || !packedCharacters.add(path)) continue;
        final base = _uniqueName(_safeFileName(role['name']?.toString() ?? role['id'].toString()), packedNames);
        await _addStorage(archive, 'characters/$base${_dotExt(path)}', path);
        _addText(archive, 'characters/$base-prompt.txt', role['prompt']?.toString() ?? '');
      }
      _addText(archive, 'music/prompt_a.txt', music?['promptA']?.toString() ?? '');
      _addText(archive, 'music/prompt_b.txt', music?['promptB']?.toString() ?? '');
      final audioA = music?['audioA']?.toString();
      final audioB = music?['audioB']?.toString();
      if (audioA != null && audioA.isNotEmpty) {
        await _addStorage(archive, 'music/audio_a${_dotExt(audioA)}', audioA);
      }
      if (audioB != null && audioB.isNotEmpty) {
        await _addStorage(archive, 'music/audio_b${_dotExt(audioB)}', audioB);
      }
      final zipped = ZipEncoder().encode(archive);
      if (zipped == null) {
        error = '패키지를 만들지 못했습니다.';
        return;
      }
      saveBytes('intronews-$projectId.zip', zipped, 'application/zip');
    } catch (caught) {
      error = '패키지를 만들지 못했습니다.';
      debugPrint('package failed: $caught');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void openStep(int step) {
    if (step < 1 || step > currentStep || step == viewingStep) return;
    viewingStep = step;
    notifyListeners();
  }

  void leaveDirtyCancelled() {}

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _runStep(int step, Map<String, dynamic> extra) async {
    busy = true;
    error = null;
    notifyListeners();
    const names = {
      1: 'generateOutline',
      2: 'generateCards',
      3: 'generateCharacters',
      4: 'generateBody',
      5: 'generateOpening',
      6: 'generateClosing',
      7: 'generateMusic',
    };
    try {
      final result = await Backend.call(names[step]!, {
        'projectId': projectId,
        ...extra,
      });
      if (result['code'] == 'TOO_MANY_ROLES') {
        final raw = result['roles'];
        pendingRoles = raw is List
            ? raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
            : [];
        pendingKeep.clear();
        error = '제안이 ${AppConfig.maxProposedCharacters}개를 넘습니다. 남길 제안을 12개 이하로 고르세요.';
        return;
      }
      pendingRoles = null;
      viewingStep = step + 1;
      await _publishListing(viewingStep);
    } on FirebaseFunctionsException catch (caught) {
      error = caught.message ?? '생성엝 실패했습니다. 다시 실행해 주세요.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _persist(int step) async {
    if (step == 1) {
      final data = {
        'title': draft['title'] ?? '',
        'pdfMode': draft['pdfMode'] ?? 'single',
        'directionNote': draft['directionNote'] ?? '',
        'mainCharacterId': draft['mainCharacterId'],
        'mainBackgroundId': draft['mainBackgroundId'],
        'extraCharacterIds': _stringList(draft['extraCharacterIds']),
        'extraBackgroundIds': _stringList(draft['extraBackgroundIds']),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await ref.update(data);
      project = {...?project, ...data};
      final order = _stringList(draft['fileOrder']);
      final selected = _selectedFileIds().toSet();
      for (var index = 0; index < order.length; index += 1) {
        final id = order[index];
        await ref.collection('files').doc(id).update({
          'order': index,
          'included': selected.contains(id),
        });
        for (final file in files) {
          if (file['id'] == id) file['included'] = selected.contains(id);
        }
      }
      return;
    }
    if (step == 2) {
      await ref.update({'synopsis': draft['synopsis'] ?? ''});
      project = {...?project, 'synopsis': draft['synopsis'] ?? ''};
      final outlines = Map<String, dynamic>.from(draft['outlines'] as Map? ?? {});
      for (final id in AppConfig.sceneIds) {
        final outline = Map<String, dynamic>.from(outlines[id] as Map? ?? {});
        await ref.collection('scenes').doc(id).set({'outline': outline}, SetOptions(merge: true));
        scene(id)['outline'] = outline;
      }
      return;
    }
    if (step == 3) {
      final cards = Map<String, dynamic>.from(draft['cards'] as Map? ?? {});
      for (final id in AppConfig.sceneIds) {
        final card = Map<String, dynamic>.from(cards[id] as Map? ?? {});
        await ref.collection('scenes').doc(id).set({'card': card}, SetOptions(merge: true));
        scene(id)['card'] = card;
      }
      return;
    }
    if (step == 4) {
      final all = Map<String, dynamic>.from(draft['roles'] as Map? ?? {});
      for (final role in roles) {
        final picked = Map<String, dynamic>.from(all[role['id']] as Map? ?? {});
        final generate = picked['generate'] == true;
        await ref.collection('characters').doc(role['id'].toString()).update({
          'selectedIndex': picked['selectedIndex'],
          'replacementPath': picked['replacementPath'],
          'generate': generate,
        });
        role['selectedIndex'] = picked['selectedIndex'];
        role['replacementPath'] = picked['replacementPath'];
        role['generate'] = generate;
      }
      return;
    }
    if (step >= 5 && step <= 7) {
      final ids = step == 5
          ? ['02', '03', '04', '05', '06', '07', '08', '09']
          : step == 6
              ? ['01']
              : ['10'];
      final prompts = Map<String, dynamic>.from(draft['prompts'] as Map? ?? {});
      for (final id in ids) {
        await ref.collection('scenes').doc(id).set({
          'flowPrompt': prompts[id] ?? '',
        }, SetOptions(merge: true));
        scene(id)['flowPrompt'] = prompts[id] ?? '';
      }
      return;
    }
    if (step == 8) {
      await ref.collection('music').doc('score').set({
        'promptA': draft['promptA'] ?? '',
        'promptB': draft['promptB'] ?? '',
      }, SetOptions(merge: true));
      music = {...?music, 'promptA': draft['promptA'] ?? '', 'promptB': draft['promptB'] ?? ''};
    }
  }

  Future<void> _writeStale(int editedStep) async {
    if (currentStep <= editedStep || editedStep >= 8) return;
    final existing = staleFromStep;
    final next = editedStep + 1;
    final value = existing == null ? next : (existing < next ? existing : next);
    project = {...?project, 'staleFromStep': value};
    await ref.update({'staleFromStep': value});
  }

  void abandonEdits() {
    if (_baseline.isEmpty) {
      dirty = false;
      notifyListeners();
      return;
    }
    draft = Map<String, dynamic>.from(jsonDecode(_baseline) as Map);
    dirty = false;
    epoch += 1;
    notifyListeners();
  }

  void _maybeCapture() {
    if (dirty || project == null) return;
    final next = _snapshotDraft();
    final encoded = jsonEncode(next);
    if (encoded == _baseline && draft.isNotEmpty) return;
    draft = next;
    _baseline = encoded;
    epoch += 1;
  }

  void _mergeFiles() {
    if (draft['fileOrder'] is! List) return;
    final ids = files.map((file) => file['id'].toString()).toList();
    final order = _stringList(draft['fileOrder']);
    final selected = _stringList(draft['selectedFileIds']);
    for (final id in ids) {
      if (!order.contains(id)) {
        order.add(id);
        if (!selected.contains(id)) selected.add(id);
      }
    }
    order.retainWhere(ids.contains);
    draft['fileOrder'] = order;
    selected.retainWhere(ids.contains);
    draft['selectedFileIds'] = selected;
    if (!dirty) {
      _baseline = jsonEncode(draft);
      return;
    }
    dirty = jsonEncode(draft) != _baseline;
  }

  Map<String, dynamic> _snapshotDraft() {
    final outlines = <String, Map<String, String>>{};
    final cards = <String, Map<String, String>>{};
    final prompts = <String, String>{};
    for (final id in AppConfig.sceneIds) {
      final item = scene(id);
      final outline = item['outline'];
      outlines[id] = {
        'title': outline is Map ? '${outline['title'] ?? ''}' : '',
        'summary': outline is Map ? '${outline['summary'] ?? ''}' : '',
      };
      final card = item['card'];
      cards[id] = {
        for (final key in cardFieldKeys) key: card is Map ? '${card[key] ?? ''}' : '',
      };
      prompts[id] = item['flowPrompt']?.toString() ?? '';
    }
    return {
      'title': project?['title']?.toString() ?? '',
      'pdfMode': project?['pdfMode']?.toString() ?? 'single',
      'directionNote': project?['directionNote']?.toString() ?? '',
      'mainCharacterId': project?['mainCharacterId'],
      'mainBackgroundId': project?['mainBackgroundId'],
      'extraCharacterIds': _stringList(project?['extraCharacterIds']),
      'extraBackgroundIds': _stringList(project?['extraBackgroundIds']),
      'fileOrder': files.map((file) => file['id'].toString()).toList(),
      'selectedFileIds': files
          .where((file) => file['included'] == true)
          .map((file) => file['id'].toString())
          .toList(),
      'synopsis': project?['synopsis']?.toString() ?? '',
      'outlines': outlines,
      'cards': cards,
      'prompts': prompts,
      'roles': {
        for (final role in roles)
          role['id'].toString(): {
            'selectedIndex': role['selectedIndex'],
            'replacementPath': role['replacementPath'],
            'generate': role['generate'] == true ||
                (role['generate'] == null && role['imagePaths'] is List && (role['imagePaths'] as List).isNotEmpty),
          },
      },
      'promptA': music?['promptA']?.toString() ?? '',
      'promptB': music?['promptB']?.toString() ?? '',
    };
  }

  bool _roleChosen(Map<String, dynamic> role) {
    final drafts = draft['roles'];
    if (drafts is! Map) return false;
    final picked = drafts[role['id'].toString()];
    if (picked is! Map) return false;
    final index = picked['selectedIndex'];
    final replacement = picked['replacementPath']?.toString() ?? '';
    if (index == -2) return false;
    if (index is int && index >= 0) return true;
    if (index == -1 && replacement.isNotEmpty) return true;
    return index == null && replacement.isNotEmpty;
  }

  List<String> _selectedFileIds() {
    final ids = files.map((file) => file['id'].toString()).toSet();
    return _stringList(draft['selectedFileIds']).where(ids.contains).toList();
  }

  bool _outlineReady(String id) {
    final outlines = draft['outlines'];
    if (outlines is! Map || outlines[id] is! Map) return false;
    final item = outlines[id] as Map;
    return _filled(item['title']) || _filled(item['summary']);
  }

  bool _cardReady(String id) {
    final cards = draft['cards'];
    if (cards is! Map || cards[id] is! Map) return false;
    final card = cards[id] as Map;
    return cardFieldKeys.any((key) => _filled(card[key]));
  }

  bool _promptReady(String id) {
    final prompts = draft['prompts'];
    if (prompts is Map && prompts.containsKey(id)) return _filled(prompts[id]);
    return _filled(scene(id)['flowPrompt']);
  }

  Future<void> _publishListing(int step) async {
    final data = <String, dynamic>{
      'listed': true,
      'lastSavedStep': step,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (step == 1) {
      final title = _pdfTitle();
      if (title != null) {
        data['title'] = title;
        draft['title'] = title;
      }
    }
    await ref.update(data);
    project = {...?project, ...data};
  }

  String? _pdfTitle() {
    final names = <String>[];
    for (final id in _selectedFileIds()) {
      for (final file in files) {
        if (file['id'].toString() != id) continue;
        final name = file['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        names.add(name.toLowerCase().endsWith('.pdf') ? name.substring(0, name.length - 4) : name);
      }
    }
    if (names.isEmpty) return null;
    if (names.length == 1) return names.first;
    return '${names.first} ? ${names.length - 1}';
  }

  bool _includeCharacter(Map<String, dynamic> role) {
    if (role['generate'] == false) return false;
    if (_selectedRoleStorage(role) == null) return false;
    if (role['generate'] == true) return true;
    final paths = role['imagePaths'];
    return paths is List && paths.isNotEmpty;
  }

  String? _selectedRoleStorage(Map<String, dynamic> role) {
    final index = role['selectedIndex'];
    final replacement = role['replacementPath']?.toString() ?? '';
    final paths = (role['imagePaths'] as List?)?.map((item) => item.toString()).toList() ?? [];
    if (index == -2) return null;
    if (index == -1 && replacement.isNotEmpty) return replacement;
    if (index is int && index >= 0 && index < paths.length && paths[index].isNotEmpty) return paths[index];
    if (index == null && replacement.isNotEmpty) return replacement;
    return null;
  }

  String _safeFileName(String name) {
    final cleaned = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    return cleaned.isEmpty ? 'character' : cleaned;
  }

  String _uniqueName(String base, Set<String> used) {
    var name = base;
    var count = 2;
    while (!used.add(name)) {
      name = '${base}_$count';
      count += 1;
    }
    return name;
  }

  bool _filled(Object? value) => value != null && value.toString().trim().isNotEmpty;

  List<String> _stringList(Object? value) {
    if (value is List) return value.map((item) => item.toString()).toList();
    return [];
  }

  Future<void> _addStorage(Archive archive, String name, String path) async {
    final bytes = await FirebaseStorage.instance.ref(path).getData(100 * 1024 * 1024);
    if (bytes == null) return;
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  void _addText(Archive archive, String name, String text) {
    final bytes = Uint8List.fromList(utf8.encode(text));
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
}

String _ext(String name, String fallback) {
  final parts = name.split('.');
  if (parts.length < 2) return fallback;
  return parts.last.toLowerCase();
}

String _dotExt(String path) {
  final ext = _ext(path, '');
  return ext.isEmpty ? '' : '.$ext';
}

String _mime(String ext) {
  switch (ext) {
    case 'pdf':
      return 'application/pdf';
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'webp':
      return 'image/webp';
    case 'mp4':
      return 'video/mp4';
    case 'webm':
      return 'video/webm';
    case 'mp3':
      return 'audio/mpeg';
    case 'wav':
      return 'audio/wav';
    case 'm4a':
      return 'audio/mp4';
    case 'zip':
      return 'application/zip';
    default:
      return 'application/octet-stream';
  }
}
