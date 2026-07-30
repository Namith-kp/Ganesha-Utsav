import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> exportCsv(String csvData) async {
  final dir = await getTemporaryDirectory();
  final path = '${dir.path}/collections_report.csv';
  final file = File(path);
  await file.writeAsString(csvData);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(path)], text: 'Ganesha Utsava Collection Report'),
  );
}
