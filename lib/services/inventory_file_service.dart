import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'product_service.dart';

typedef InventoryFilePicker = Future<FilePickerResult?> Function();

class InventoryFileService {
  const InventoryFileService({this.picker});

  final InventoryFilePicker? picker;

  Future<String?> pickCsv() async {
    final selection = picker == null
        ? await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['csv'],
            allowMultiple: false,
            withData: false,
          )
        : await picker!();
    if (selection == null || selection.files.isEmpty) return null;
    final selected = selection.files.single;
    if (p.extension(selected.name).toLowerCase() != '.csv') {
      throw const FormatException('Select a CSV file.');
    }
    final path = selected.path;
    if (path == null) {
      throw const FormatException('The selected CSV file is unavailable.');
    }
    final file = File(path);
    if (selected.size > 20 * 1024 * 1024 ||
        await file.length() > 20 * 1024 * 1024) {
      throw const FormatException('CSV file is larger than 20 MB.');
    }
    return utf8.decode(await file.readAsBytes());
  }

  Future<void> shareBackup(ProductService service) async {
    final backup = await service.createBackup();
    final file = await _temporaryFile('stocklens-backup', 'json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(backup),
      flush: true,
    );
    await SharePlus.instance.share(
      ShareParams(
        subject: 'StockLens inventory backup',
        text: 'StockLens inventory backup. Keep this file private.',
        files: [XFile(file.path, mimeType: 'application/json')],
      ),
    );
  }

  Future<bool> pickAndRestoreBackup(ProductService service) async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      allowMultiple: false,
      withData: false,
    );
    final path = selection?.files.single.path;
    if (path == null) return false;
    final file = File(path);
    if (await file.length() > 100 * 1024 * 1024) {
      throw const FormatException('Backup file is larger than 100 MB.');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException(
        'The selected file is not a StockLens backup.',
      );
    }
    await service.restoreBackup(Map<String, Object?>.from(decoded));
    return true;
  }

  Future<void> shareCsv(ProductService service) async {
    final file = await _temporaryFile('stocklens-inventory', 'csv');
    await file.writeAsString(await service.inventoryCsv(), flush: true);
    await SharePlus.instance.share(
      ShareParams(
        subject: 'StockLens inventory export',
        files: [XFile(file.path, mimeType: 'text/csv')],
      ),
    );
  }

  Future<File> _temporaryFile(String prefix, String extension) async {
    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    return File(p.join(directory.path, '$prefix-$timestamp.$extension'));
  }
}
