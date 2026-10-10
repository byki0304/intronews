import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class DroppedFile {
  const DroppedFile(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

class FileDropRegion extends StatefulWidget {
  const FileDropRegion({super.key, required this.child, required this.onFiles});

  final Widget child;
  final Future<void> Function(List<DroppedFile> files) onFiles;

  @override
  State<FileDropRegion> createState() => _FileDropRegionState();
}

class _FileDropRegionState extends State<FileDropRegion> {
  final _key = GlobalKey();
  late final JSFunction _prevent;
  late final JSFunction _drop;

  @override
  void initState() {
    super.initState();
    _prevent = ((web.Event event) {
      event.preventDefault();
    }).toJS;
    _drop = ((web.Event event) {
      event.preventDefault();
      final drag = event as web.DragEvent;
      if (!_contains(Offset(drag.clientX.toDouble(), drag.clientY.toDouble()))) return;
      final list = drag.dataTransfer?.files;
      if (list == null || list.length == 0) return;
      final files = <web.File>[];
      for (var index = 0; index < list.length; index += 1) {
        final file = list.item(index);
        if (file != null) files.add(file);
      }
      unawaited(_read(files));
    }).toJS;
    web.document.addEventListener('dragover', _prevent);
    web.document.addEventListener('drop', _drop);
  }

  @override
  void dispose() {
    web.document.removeEventListener('dragover', _prevent);
    web.document.removeEventListener('drop', _drop);
    super.dispose();
  }

  Future<void> _read(List<web.File> files) async {
    final dropped = <DroppedFile>[];
    for (final file in files) {
      final reader = web.FileReader();
      final completer = Completer<Uint8List>();
      reader.onloadend = ((web.Event _) {
        final result = reader.result;
        if (result.isA<JSArrayBuffer>()) {
          completer.complete((result as JSArrayBuffer).toDart.asUint8List());
        } else {
          completer.complete(Uint8List(0));
        }
      }).toJS;
      reader.readAsArrayBuffer(file);
      final bytes = await completer.future;
      if (bytes.isEmpty) continue;
      dropped.add(DroppedFile(file.name, bytes));
    }
    if (!mounted || dropped.isEmpty) return;
    await widget.onFiles(dropped);
  }

  bool _contains(Offset global) {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return false;
    final local = box.globalToLocal(global);
    return local.dx >= 0 && local.dy >= 0 && local.dx <= box.size.width && local.dy <= box.size.height;
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _key,
      child: widget.child,
    );
  }
}
