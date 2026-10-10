import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../platform/file_drop.dart';
import '../state/project_controller.dart';

class ProjectPage extends StatefulWidget {
  const ProjectPage({super.key, required this.projectId, required this.onExit});

  final String projectId;
  final VoidCallback onExit;

  @override
  State<ProjectPage> createState() => _ProjectPageState();
}

class _ProjectPageState extends State<ProjectPage> {
  late final ProjectController controller;
  final fields = <String, TextEditingController>{};
  final player = AudioPlayer();
  final urls = <String, Future<String>>{};
  int appliedEpoch = -1;
  bool applying = false;

  @override
  void initState() {
    super.initState();
    controller = ProjectController(widget.projectId)..listen();
    controller.addListener(_sync);
  }

  @override
  void dispose() {
    controller.removeListener(_sync);
    controller.dispose();
    for (final field in fields.values) {
      field.dispose();
    }
    player.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    if (!controller.dirty && appliedEpoch != controller.epoch) {
      applying = true;
      _apply();
      applying = false;
      appliedEpoch = controller.epoch;
    }
    setState(() {});
  }

  void _apply() {
    final draft = controller.draft;
    _text('title', '${draft['title'] ?? ''}');
    _text('note', '${draft['directionNote'] ?? ''}');
    _text('synopsis', '${draft['synopsis'] ?? ''}');
    _text('promptA', '${draft['promptA'] ?? ''}');
    _text('promptB', '${draft['promptB'] ?? ''}');
    final outlines = draft['outlines'];
    final cards = draft['cards'];
    final prompts = draft['prompts'];
    for (final id in AppConfig.sceneIds) {
      if (outlines is Map && outlines[id] is Map) {
        _text('o-$id-title', '${outlines[id]['title'] ?? ''}');
        _text('o-$id-summary', '${outlines[id]['summary'] ?? ''}');
      }
      if (cards is Map && cards[id] is Map) {
        for (final key in cardFieldKeys) {
          _text('c-$id-$key', '${cards[id][key] ?? ''}');
        }
      }
      if (prompts is Map) _text('p-$id', '${prompts[id] ?? ''}');
    }
  }

  void _text(String key, String value) {
    final field = fields.putIfAbsent(key, TextEditingController.new);
    if (field.text != value) field.text = value;
  }

  TextEditingController _field(String key) {
    return fields.putIfAbsent(key, TextEditingController.new);
  }

  ButtonStyle get _hoverStyle => _loadButtonStyle;

  Future<String> _url(String path) {
    return urls.putIfAbsent(path, () => FirebaseStorage.instance.ref(path).getDownloadURL());
  }

  Color get accent => controller.genre == 'lecture'
      ? const Color(AppColors.lecture)
      : const Color(AppColors.news);

  Future<void> _move(int step) async {
    if (!await _confirmDiscard()) return;
    if (controller.dirty) controller.abandonEdits();
    if (step < 1) {
      widget.onExit();
      return;
    }
    controller.openStep(step);
  }

  Future<bool> _confirmDiscard() async {
    if (!controller.dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('저장하지 않은 편집'),
        content: const Text('이 단계의 편집을 버리고 이동할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('계속 편집')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('버리기')),
        ],
      ),
    );
    return discard == true;
  }

  @override
  Widget build(BuildContext context) {
    if (controller.loading || controller.project == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final bottomLift = MediaQuery.sizeOf(context).height * 0.08;
    return Stack(
      children: [
        Column(
          children: [
            _steps(wide),
            if (controller.busy) const LinearProgressIndicator(),
            if (controller.staleFromStep != null && controller.viewingStep >= controller.staleFromStep!)
              MaterialBanner(
                content: Text('${controller.staleFromStep! - 1}단계로 돌아가 다시 생성해 주세요. 이후 산출물은 다시 생성 필요합니다.'),
                actions: [
                  TextButton(
                    onPressed: () => _move(controller.staleFromStep! - 1),
                    child: const Text('이동'),
                  ),
                ],
              ),
            if (controller.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(controller.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 88 + bottomLift),
                children: [
                  _rail(),
                  const SizedBox(height: 16),
                  _body(),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: bottomLift,
          child: Material(
            color: const Color(AppColors.paper).withValues(alpha: 0.7),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0x14000000))),
              ),
              child: _actions(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _steps(bool wide) {
    return SizedBox(
      height: 64,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        itemCount: AppConfig.stepTitles.length,
        itemBuilder: (context, index) {
          final step = index + 1;
          final selected = controller.viewingStep == step;
          final enabled = step <= controller.currentStep;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text('$step. ${AppConfig.stepTitles[index]}'),
              selected: selected,
              onSelected: !enabled || controller.busy
                  ? null
                  : (_) {
                      if (step == controller.viewingStep) return;
                      _move(step);
                    },
            ),
          );
        },
      ),
    );
  }

  Widget _rail() {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: AppConfig.sceneIds.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final id = AppConfig.sceneIds[index];
          final item = controller.scene(id);
          return Container(
            width: 108,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _focused(id) ? accent : Colors.black12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(id, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(_statusLabel(item), style: const TextStyle(fontSize: 11)),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _focused(String id) {
    final step = controller.viewingStep;
    if (step == 5) return int.parse(id) >= 2 && int.parse(id) <= 9;
    if (step == 6) return id == '01';
    if (step == 7) return id == '10';
    return true;
  }

  String _statusLabel(Map<String, dynamic> item) {
    final status = item['status']?.toString() ?? '';
    final label = switch (status) {
      'video' => '영상 있음',
      'prompt' => '프롬프트',
      'card' => '카드',
      'outline' => '개요',
      _ => '대기',
    };
    final produced = switch (status) {
      'video' => 8,
      'prompt' => item['id'] == '01'
          ? 6
          : item['id'] == '10'
              ? 7
              : 5,
      'card' => 3,
      'outline' => 2,
      _ => 0,
    };
    final stale = controller.staleFromStep;
    if (stale != null && produced >= stale) return '$label · 다시 생성 필요';
    return label;
  }

  Widget _body() {
    return switch (controller.viewingStep) {
      1 => _step1(),
      2 => _step2(),
      3 => _step3(),
      4 => _step4(),
      8 => _step8(),
      _ => _prompts(),
    };
  }

  Widget _step1() {
    final draft = controller.draft;
    final order = draft['fileOrder'] is List
        ? (draft['fileOrder'] as List).map((item) => item.toString()).toList()
        : controller.files.map((file) => file['id'].toString()).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _field('title'),
          decoration: const InputDecoration(labelText: '프로젝트 제목'),
          onChanged: (value) {
            if (!applying) controller.setField('title', value);
          },
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'single', label: Text('PDF 1개')),
            ButtonSegment(value: 'multi', label: Text('PDF 여러 개')),
          ],
          selected: {(draft['pdfMode'] ?? 'single').toString()},
          onSelectionChanged: (value) => controller.setField('pdfMode', value.first),
        ),
        const SizedBox(height: 12),
        _pdfWindow(order),
        const SizedBox(height: 16),
        _assetGroup('character', '메인 캐릭터'),
        const SizedBox(height: 16),
        _assetGroup('background', '메인 배경'),
        const SizedBox(height: 16),
        Text('연출 요청사항 메모장', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _field('note'),
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'AI에게 요청하고 싶은 내용을 적어 주세요',
            hintStyle: TextStyle(color: Color(0xFFB0B0B0)),
          ),
          onChanged: (value) {
            if (!applying) controller.setField('directionNote', value);
          },
        ),
      ],
    );
  }

  Widget _pdfWindow(List<String> order) {
    final files = <Map<String, dynamic>>[];
    for (final id in order) {
      for (final item in controller.files) {
        if (item['id'] == id) files.add(item);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('PDF', style: Theme.of(context).textTheme.titleMedium),
            if (files.isNotEmpty) ...[
              const SizedBox(width: 12),
              TextButton(
                style: _hoverStyle,
                onPressed: controller.busy || !files.any((file) => controller.isFileIncluded(file['id'].toString()))
                    ? null
                    : () async {
                        final ids = files
                            .map((file) => file['id'].toString())
                            .where(controller.isFileIncluded)
                            .toList();
                        await controller.deleteFiles(ids);
                      },
                child: const Text('삭제'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        FileDropRegion(
          onFiles: (dropped) => controller.addPdfPayloads(
            dropped.map((file) => (name: file.name, bytes: file.bytes)).toList(),
          ),
          child: _PdfDropBox(
            files: files,
            marked: files.map((file) => file['id'].toString()).where(controller.isFileIncluded).toSet(),
            busy: controller.busy,
            onToggle: controller.toggleFileIncluded,
            onUpload: controller.busy ? null : controller.addPdfs,
          ),
        ),
      ],
    );
  }

  Widget _assetGroup(String kind, String mainLabel) {
    final items = controller.byKind(kind);
    final mainKey = kind == 'character' ? 'mainCharacterId' : 'mainBackgroundId';
    final mainId = controller.draft[mainKey]?.toString();
    final marks = controller.includedIds(kind).where((id) => items.any((item) => item['id'] == id)).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final thumb = (constraints.maxWidth * 0.12).clamp(80.0, 100.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(mainLabel, style: Theme.of(context).textTheme.titleMedium),
                if (items.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  TextButton(
                    style: _hoverStyle,
                    onPressed: controller.busy || marks.isEmpty
                        ? null
                        : () => controller.deleteAssets(kind, marks),
                    child: const Text('삭제'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: [
                for (final item in items)
                  _ThumbTile(
                    size: thumb,
                    name: item['name']?.toString() ?? item['id'].toString(),
                    path: item['storagePath']?.toString() ?? '',
                    imageUrl: _url,
                    selected: item['id'].toString() == mainId,
                    checked: controller.isIncluded(kind, item['id'].toString()),
                    onSelect: () => controller.setMain(kind, item['id'].toString()),
                    onCheck: (value) => controller.toggleIncluded(kind, item['id'].toString(), value),
                  ),
                _PlusUpload(
                  size: thumb,
                  enabled: !controller.busy,
                  onTap: () async {
                    final id = await controller.uploadAsset(kind);
                    if (id != null) controller.setMain(kind, id);
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _step2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _field('synopsis'),
          minLines: 4,
          maxLines: 8,
          decoration: const InputDecoration(labelText: '시놉시스'),
          onChanged: (value) {
            if (!applying) controller.setField('synopsis', value);
          },
        ),
        for (final id in AppConfig.sceneIds) ...[
          const SizedBox(height: 12),
          Text('장면 $id', style: Theme.of(context).textTheme.titleMedium),
          Text('근거 PDF: ${((controller.scene(id)['sourcePdfNames'] as List?) ?? []).join(', ')}'),
          TextField(
            controller: _field('o-$id-title'),
            decoration: const InputDecoration(labelText: '제목'),
            onChanged: (value) {
              if (!applying) controller.setOutline(id, 'title', value);
            },
          ),
          TextField(
            controller: _field('o-$id-summary'),
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: '개요'),
            onChanged: (value) {
              if (!applying) controller.setOutline(id, 'summary', value);
            },
          ),
        ],
      ],
    );
  }

  Widget _step3() {
    final pending = controller.pendingRoles;
    final keys = controller.genre == 'lecture'
        ? cardFieldKeys.where((key) => key != 'title').toList()
        : cardFieldKeys
            .where((key) =>
                ![
                  'title',
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
                ].contains(key))
            .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pending != null) _pending(pending),
        for (final id in AppConfig.sceneIds) ...[
          Text('장면 $id', style: Theme.of(context).textTheme.titleMedium),
          Text('근거 PDF: ${((controller.scene(id)['sourcePdfNames'] as List?) ?? []).join(', ')}'),
          TextField(
            controller: _field('c-$id-title'),
            decoration: InputDecoration(labelText: _label('title')),
            onChanged: (value) {
              if (!applying) controller.setCard(id, 'title', value);
            },
          ),
          for (final key in keys)
            TextField(
              controller: _field('c-$id-$key'),
              minLines: key == 'description' ? 2 : 1,
              maxLines: 4,
              decoration: InputDecoration(labelText: _label(key)),
              onChanged: (value) {
                if (!applying) controller.setCard(id, key, value);
              },
            ),
          const Divider(),
        ],
      ],
    );
  }

  Widget _pending(List<Map<String, dynamic>> roles) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('제안이 ${AppConfig.maxProposedCharacters}개를 넘습니다. 남길 제안을 12개 이하로 고르세요.'),
            for (final role in roles)
              CheckboxListTile(
                value: controller.pendingKeep.contains(role['id']?.toString()),
                onChanged: (value) => controller.togglePending(role['id'].toString(), value == true),
                title: Text(role['name']?.toString() ?? ''),
                subtitle: Text((role['sceneIds'] as List?)?.join(', ') ?? ''),
              ),
            FilledButton(
              onPressed: controller.busy ||
                      controller.pendingKeep.isEmpty ||
                      controller.pendingKeep.length > AppConfig.maxProposedCharacters
                  ? null
                  : controller.confirmPendingRoles,
              child: const Text('고른 제안만 남기기'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step4() {
    if (controller.roles.isEmpty) {
      return const Text('조연이 없습니다. 선택 없이 다음으로 갈 수 있습니다.');
    }
    final drafts = controller.draft['roles'];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 4 : 3;
        final gap = 12.0;
        final tile = columns == 1 ? constraints.maxWidth : (constraints.maxWidth - gap * (columns - 1)) / columns;
        final rows = <Widget>[];
        for (var index = 0; index < controller.roles.length; index += columns) {
          final slice = controller.roles.skip(index).take(columns).toList();
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var column = 0; column < columns; column++) ...[
                  if (column > 0) const SizedBox(width: 12),
                  SizedBox(
                    width: tile,
                    child: column < slice.length ? _roleCard(slice[column], drafts, tile) : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          );
          rows.add(const SizedBox(height: 12));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('만들 캐릭터를 9개까지 체크한 뒤 생성하세요. 생성된 이미지를 체크하면 그 이미지를 사용합니다.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: controller.busy || controller.generatePickCount == 0 ? null : controller.generateCheckedRoles,
              child: const Text('선택한 캐릭터 생성'),
            ),
            const SizedBox(height: 12),
            ...rows,
          ],
        );
      },
    );
  }

  Widget _roleCard(Map<String, dynamic> role, Object? drafts, double tile) {
    final roleId = role['id'].toString();
    final paths = (role['imagePaths'] as List?)?.map((item) => item.toString()).toList() ?? [];
    final generated = paths.isEmpty ? '' : paths.first;
    final replacement = _replacement(drafts, roleId);
    final picked = drafts is Map && drafts[roleId] is Map ? drafts[roleId] as Map : const {};
    final index = picked['selectedIndex'];
    final generatedOn = index is int && index >= 0;
    final replacementOn = index == -1 && replacement != null;
    final thumb = tile >= 80 ? tile.clamp(80.0, 100.0).toDouble() : tile;
    final members = (role['members'] as List?)?.map((item) => item.toString()).where((item) => item.isNotEmpty).toList() ?? [];
    final grouped = role['grouped'] == true && members.length >= 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: controller.wantsGeneration(role),
                visualDensity: VisualDensity.compact,
                onChanged: controller.busy ? null : (value) => controller.toggleGenerate(roleId, value == true),
              ),
            ),
            const SizedBox(width: 4),
            const Expanded(child: Text('생성')),
          ],
        ),
        Text(
          role['name']?.toString() ?? roleId,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text('장면 ${(role['sceneIds'] as List?)?.join(', ') ?? ''}'),
        if (grouped) Text('함께 ${members.join(', ')}', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (generated.isNotEmpty)
              _ThumbTile(
                size: thumb,
                name: role['name']?.toString() ?? roleId,
                path: generated,
                imageUrl: _url,
                selected: generatedOn,
                checked: generatedOn,
                onSelect: () => controller.selectRole(roleId, 0),
                onCheck: (value) => value ? controller.selectRole(roleId, 0) : controller.clearRolePick(roleId),
              ),
            if (replacement != null)
              _ThumbTile(
                size: thumb,
                name: '수정본',
                path: replacement,
                imageUrl: _url,
                selected: replacementOn,
                checked: replacementOn,
                onSelect: () => controller.selectRole(roleId, -1),
                onCheck: (value) => value ? controller.selectRole(roleId, -1) : controller.clearRolePick(roleId),
              ),
            _PlusUpload(
              size: thumb,
              enabled: !controller.busy,
              onTap: () => controller.replaceRoleImage(roleId),
            ),
          ],
        ),
        if (generated.isNotEmpty) ...[
          TextButton(
            style: _hoverStyle,
            onPressed: controller.busy ? null : () => controller.regenerateRole(roleId),
            child: const Text('다시 만들기'),
          ),
          TextButton(
            style: _hoverStyle,
            onPressed: () {
              final ext = generated.contains('.') ? generated.split('.').last : 'jpg';
              controller.downloadPath(generated, '${role['name']}.$ext');
            },
            child: const Text('이미지 다운로드'),
          ),
          TextButton(
            style: _hoverStyle,
            onPressed: () => controller.downloadRolePrompt(role),
            child: const Text('프롬프트 다운로드'),
          ),
        ],
      ],
    );
  }

  String? _replacement(Object? drafts, String roleId) {
    if (drafts is! Map || drafts[roleId] is! Map) return null;
    final path = drafts[roleId]['replacementPath']?.toString();
    if (path == null || path.isEmpty) return null;
    return path;
  }

  Widget _prompts() {
    final step = controller.viewingStep;
    final ids = step == 5
        ? ['02', '03', '04', '05', '06', '07', '08', '09']
        : step == 6
            ? ['01']
            : ['10'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          step == 5 ? '본편 02–09만 수정합니다.' : step == 6 ? '오프닝 01만 수정합니다.' : '클로징 10만 수정합니다.',
        ),
        for (final id in ids) ...[
          const SizedBox(height: 12),
          Text('장면 $id'),
          TextField(
            controller: _field('p-$id'),
            minLines: 8,
            maxLines: 16,
            decoration: const InputDecoration(labelText: '영어 Flow 프롬프트'),
            onChanged: (value) {
              if (!applying) controller.setPrompt(id, value);
            },
          ),
        ],
      ],
    );
  }

  Widget _step8() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('완성 패키지', style: Theme.of(context).textTheme.titleLarge),
        const Text('Flow에서 16:9, 8초 영상을 만든 뒤 여기에 올립니다. BGM은 120초이며 Premiere에서 길이에 맞게 자릅니다.'),
        for (final id in AppConfig.sceneIds) _scenePackage(id),
        const Divider(),
        _musicCard('A', 'promptA', controller.music?['audioA']?.toString(), 'a'),
        _musicCard('B', 'promptB', controller.music?['audioB']?.toString(), 'b'),
        const SizedBox(height: 12),
        FilledButton(
          style: _hoverStyle,
          onPressed: controller.busy ? null : controller.downloadPackage,
          child: const Text('Premiere 패키지 다운로드'),
        ),
      ],
    );
  }

  Widget _scenePackage(String id) {
    final item = controller.scene(id);
    final prompt = item['flowPrompt']?.toString() ?? '';
    final refs = (item['referenceAssetIds'] as List?)?.map((path) => path.toString()).toList() ?? [];
    final video = item['videoStoragePath']?.toString();
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('장면 $id · ${_statusLabel(item)}'),
            Text('근거 PDF: ${((item['sourcePdfNames'] as List?) ?? []).join(', ')}'),
            const SizedBox(height: 8),
            SelectableText(prompt.isEmpty ? '프롬프트가 없습니다.' : prompt),
            Wrap(
              children: [
                TextButton(
                  onPressed: prompt.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: prompt));
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('프롬프트를 복사했습니다.')));
                        },
                  child: const Text('프롬프트 복사'),
                ),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(AppConfig.flowWebUrl),
                    webOnlyWindowName: '_blank',
                  ),
                  child: const Text('Flow 열기'),
                ),
                for (var index = 0; index < refs.length; index++)
                TextButton(
                  style: _hoverStyle,
                  onPressed: () => controller.downloadPath(refs[index], 'scene-$id-ref-$index${_suffix(refs[index])}'),
                  child: Text('참조 ${index + 1} 다운로드'),
                ),
                TextButton(
                  style: _hoverStyle,
                  onPressed: controller.busy ? null : () => controller.uploadSceneVideo(id),
                  child: const Text('영상 업로드'),
                ),
                if (video != null && video.isNotEmpty)
                  TextButton(
                    style: _hoverStyle,
                    onPressed: () => controller.downloadPath(video, 'scene-$id${_suffix(video)}'),
                    child: const Text('영상 다운로드'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _musicCard(String label, String draftKey, String? audioPath, String slot) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('음악 $label'),
            TextField(
              controller: _field(draftKey),
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(labelText: '영어 음악 프롬프트'),
              onChanged: (value) {
                if (!applying) controller.setField(draftKey, value);
              },
            ),
            Wrap(
              children: [
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _field(draftKey).text));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('음악 $label 프롬프트를 복사했습니다.')));
                  },
                  child: const Text('프롬프트 복사'),
                ),
                TextButton(
                  style: _hoverStyle,
                  onPressed: () => controller.uploadMusic(slot),
                  child: const Text('음원 업로드'),
                ),
                if (audioPath != null && audioPath.isNotEmpty) ...[
                  TextButton(onPressed: () => _play(audioPath), child: const Text('재생')),
                  TextButton(
                    style: _hoverStyle,
                    onPressed: () => controller.downloadPath(audioPath, 'music-$label${_suffix(audioPath)}'),
                    child: const Text('다운로드'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _play(String path) async {
    final url = await _url(path);
    await player.setUrl(url);
    await player.play();
  }

  Widget _actions() {
    final step = controller.viewingStep;
    final retry = controller.error != null && controller.pendingRoles == null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: controller.busy ? null : () => _move(step - 1),
            child: Text(step == 1 ? '프로젝트 목록' : '이전'),
          ),
          OutlinedButton(
            onPressed: controller.canSave ? controller.saveCurrent : null,
            child: const Text('저장'),
          ),
          if (step < 8)
            FilledButton(
              onPressed: controller.canGoNext && controller.pendingRoles == null ? controller.goNext : null,
              child: Text(retry ? '다시 실행' : '다음'),
            ),
        ],
      ),
    );
  }
}

const _loadButtonStyle = ButtonStyle(
  backgroundColor: WidgetStateProperty.fromMap({
    WidgetState.hovered: Color(0xFFF0F0F0),
  }),
);

class _PlusUpload extends StatefulWidget {
  const _PlusUpload({required this.size, required this.enabled, required this.onTap});

  final double size;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_PlusUpload> createState() => _PlusUploadState();
}

class _PlusUploadState extends State<_PlusUpload> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: Container(
          width: widget.size,
          height: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovering ? const Color(0xFFF0F0F0) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFB0B0B0)),
          ),
          child: const Text(
            '+\n(파일업로드)',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, height: 1.2),
          ),
        ),
      ),
    );
  }
}

class _ThumbTile extends StatelessWidget {
  const _ThumbTile({
    required this.size,
    required this.name,
    required this.path,
    required this.imageUrl,
    required this.selected,
    required this.checked,
    required this.onSelect,
    required this.onCheck,
  });

  final double size;
  final String name;
  final String path;
  final Future<String> Function(String path) imageUrl;
  final bool selected;
  final bool checked;
  final VoidCallback onSelect;
  final ValueChanged<bool> onCheck;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onSelect,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? const Color(AppColors.news) : const Color(0x22000000),
                  width: selected ? 3 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: path.isEmpty
                  ? const ColoredBox(color: Color(0xFFE8E8E8))
                  : FutureBuilder<String>(
                      future: imageUrl(path),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const ColoredBox(color: Color(0xFFE8E8E8));
                        return Image.network(snapshot.data!, width: size, height: size, fit: BoxFit.cover);
                      },
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: checked,
                  visualDensity: VisualDensity.compact,
                  onChanged: (value) => onCheck(value == true),
                ),
              ),
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PdfDropBox extends StatefulWidget {
  const _PdfDropBox({
    required this.files,
    required this.marked,
    required this.busy,
    required this.onToggle,
    required this.onUpload,
  });

  final List<Map<String, dynamic>> files;
  final Set<String> marked;
  final bool busy;
  final void Function(String id, bool selected) onToggle;
  final VoidCallback? onUpload;

  @override
  State<_PdfDropBox> createState() => _PdfDropBoxState();
}

class _PdfDropBoxState extends State<_PdfDropBox> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: GestureDetector(
        onTap: widget.onUpload,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: hovering ? const Color(0xFFF0F0F0) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFB0B0B0)),
          ),
          child: Column(
            children: [
              for (final file in widget.files)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: Row(
                    children: [
                      Checkbox(
                        value: widget.marked.contains(file['id'].toString()),
                        onChanged: widget.busy
                            ? null
                            : (value) => widget.onToggle(file['id'].toString(), value == true),
                      ),
                      Expanded(child: Text(file['name']?.toString() ?? file['id'].toString())),
                    ],
                  ),
                ),
              SizedBox(
                height: 80,
                child: Center(
                  child: Text(
                    '+\n(파일업로드)',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: hovering ? const Color(0xFF333333) : const Color(0xFF888888)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _label(String key) {
  const labels = {
    'title': '제목',
    'description': '장면 설명',
    'characters': '등장 캐릭터',
    'region': '지역',
    'place': '장소',
    'background': '배경',
    'era': '시대',
    'year': '연도',
    'action': '액션',
    'dialogue': '대사',
    'narration': '내레이션',
    'cameraMove': '카메라',
    'shotChange': '숏 변화',
    'mood': '분위기',
    'sfx': '효과음',
    'bgm': 'BGM',
    'generationNotes': '생성 노트',
    'visualStorytellingGoal': '시각적 목표',
    'emotionalTone': '감정 톤',
    'scenePurpose': '장면 목적',
    'directorIntent': '연출 의도',
    'timeOfDay': '시간대',
    'weather': '날씨',
    'lighting': '조명',
    'colorTone': '색감',
    'visualFocus': '시각적 초점',
    'transitionToNext': '다음 장면 연결',
  };
  return labels[key] ?? key;
}

String _suffix(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return '';
  return path.substring(dot);
}
