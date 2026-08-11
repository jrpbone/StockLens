import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

abstract interface class ProductImageStorage {
  Future<String?> persist(String? sourcePath);
  Future<String> persistBytes(List<int> bytes, {required String extension});
  Future<void> delete(String? imagePath);
}

class LocalProductImageStorage implements ProductImageStorage {
  Future<Directory> _imageDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'product_images'));
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<String?> persist(String? sourcePath) async {
    if (sourcePath == null || sourcePath.trim().isEmpty) return null;
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const FileSystemException('Selected product image is unavailable.');
    }
    final directory = await _imageDirectory();
    final sourceAbsolute = p.normalize(source.absolute.path);
    if (p.isWithin(directory.path, sourceAbsolute)) return sourceAbsolute;

    final extension = p.extension(sourcePath).toLowerCase();
    final destination = p.join(
      directory.path,
      '${const Uuid().v4()}${extension.isEmpty ? '.img' : extension}',
    );
    return (await source.copy(destination)).path;
  }

  @override
  Future<String> persistBytes(
    List<int> bytes, {
    required String extension,
  }) async {
    final directory = await _imageDirectory();
    final safeExtension = RegExp(r'^\.[a-zA-Z0-9]{1,8}$').hasMatch(extension)
        ? extension.toLowerCase()
        : '.img';
    final destination = File(
      p.join(directory.path, '${const Uuid().v4()}$safeExtension'),
    );
    await destination.writeAsBytes(bytes, flush: true);
    return destination.path;
  }

  @override
  Future<void> delete(String? imagePath) async {
    if (imagePath == null || imagePath.trim().isEmpty) return;
    final directory = await _imageDirectory();
    final candidate = p.normalize(File(imagePath).absolute.path);
    if (!p.isWithin(directory.path, candidate)) return;
    final file = File(candidate);
    if (await file.exists()) await file.delete();
  }
}
