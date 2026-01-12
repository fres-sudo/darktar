import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'blob_storage.dart';

/// Local filesystem implementation of [BlobStorage].
class FileSystemStorage implements BlobStorage {
  FileSystemStorage(this.basePath);

  /// The base directory for storage.
  final String basePath;

  @override
  Future<void> store(String path, Uint8List bytes) async {
    final file = File(p.join(basePath, path));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<Uint8List?> retrieve(String path) async {
    final file = File(p.join(basePath, path));
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  @override
  Future<void> delete(String path) async {
    final file = File(p.join(basePath, path));
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<bool> exists(String path) async {
    final file = File(p.join(basePath, path));
    return file.exists();
  }

  @override
  Future<List<String>> list(String prefix) async {
    final dir = Directory(p.join(basePath, prefix));
    if (!await dir.exists()) {
      return [];
    }

    final entities = await dir.list(recursive: true).toList();
    return entities
        .whereType<File>()
        .map((f) => p.relative(f.path, from: basePath))
        .toList();
  }
}
