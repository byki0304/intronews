import 'dart:typed_data';

import 'package:flutter/material.dart';

class DroppedFile {
  const DroppedFile(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

class FileDropRegion extends StatelessWidget {
  const FileDropRegion({super.key, required this.child, required this.onFiles});

  final Widget child;
  final Future<void> Function(List<DroppedFile> files) onFiles;

  @override
  Widget build(BuildContext context) => child;
}
