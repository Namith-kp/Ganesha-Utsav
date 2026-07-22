import 'dart:async';
import 'dart:convert';
import '../utils/platform_io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _baseUrl = 'https://pub-2e6c9cb2a1eb4eb98c8bae3105ebf165.r2.dev';
const String _prefKey = 'panoramas_downloaded';

/// Progress snapshot emitted during download
class DownloadProgress {
  final int completed;
  final int total;
  final bool isDone;
  final String? error;

  const DownloadProgress({
    required this.completed,
    required this.total,
    this.isDone = false,
    this.error,
  });

  double get fraction => total == 0 ? 0 : completed / total;
  String get label => '$completed / $total images';
}

class PanoramaDownloadService {
  // ── Public helpers ──────────────────────────────────────────────────────────

  /// Directory where panorama .webp files are stored.
  static Future<Directory> get panoramaDir async {
    if (kIsWeb) return Directory('');
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/panoramas');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Returns the local [File] for [panoid], or null if not downloaded yet.
  static Future<File?> localFileFor(String panoid) async {
    if (kIsWeb) return null;
    final dir = await panoramaDir;
    final file = File('${dir.path}/$panoid.webp');
    return await file.exists() ? file : null;
  }

  /// Whether the one-time full download has been completed.
  static Future<bool> get isDownloadComplete async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  static Future<void> _markDownloadComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
  }

  // ── Download all panoramas ──────────────────────────────────────────────────

  /// Fetches metadata, then downloads every missing .webp file.
  /// Yields [DownloadProgress] events. Skips already-downloaded files.
  Stream<DownloadProgress> downloadAll() async* {
    if (kIsWeb) {
      yield const DownloadProgress(completed: 0, total: 0, isDone: true);
      return;
    }

    // 1. Fetch node list
    List<String> ids;
    try {
      ids = await _fetchAllIds();
    } catch (e) {
      yield DownloadProgress(
        completed: 0,
        total: 0,
        error: 'Failed to load metadata: $e',
      );
      return;
    }

    final dir = await panoramaDir;
    final total = ids.length;
    int completed = 0;

    // Emit initial state immediately
    yield DownloadProgress(completed: 0, total: total);

    // 2. Download concurrently (max 4 at a time to avoid overwhelming the CDN)
    final client = http.Client();
    try {
      final semaphore = _Semaphore(4);

      final futures = ids.map((id) async {
        await semaphore.acquire();
        try {
          final file = File('${dir.path}/$id.webp');
          if (!await file.exists()) {
            await _downloadFile(client, '$_baseUrl/$id.webp', file);
          }
        } catch (e) {
          debugPrint('Failed to download $id: $e');
        } finally {
          semaphore.release();
          completed++;
        }
      });

      // Yield progress periodically while downloads run
      final allFutures = Future.wait(futures);
      while (true) {
        // Wait a short tick and yield the current count
        await Future.delayed(const Duration(milliseconds: 300));
        yield DownloadProgress(completed: completed, total: total);
        if (completed >= total) break;
        // Check if futures resolved early (all done before tick)
        final done = await allFutures
            .then((_) => true)
            .timeout(Duration.zero, onTimeout: () => false);
        if (done) break;
      }

      // Final await to ensure everything is flushed
      await allFutures;
      yield DownloadProgress(completed: total, total: total, isDone: true);
      await _markDownloadComplete();
    } finally {
      client.close();
    }
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  Future<List<String>> _fetchAllIds() async {
    // Try mapped_metadata.json first
    for (final path in ['mapped_metadata.json', 'metadata.json']) {
      try {
        final response = await http.get(Uri.parse('$_baseUrl/$path'));
        if (response.statusCode == 200) {
          final List<dynamic> nodes = json.decode(response.body);
          return nodes.map((n) => n['id'] as String).toList();
        }
      } catch (_) {}
    }
    throw Exception('Could not load metadata from R2');
  }

  Future<void> _downloadFile(http.Client client, String url, File dest) async {
    final response = await client.get(Uri.parse(url));
    if (response.statusCode == 200) {
      await dest.writeAsBytes(response.bodyBytes);
    } else {
      throw Exception('HTTP ${response.statusCode} for $url');
    }
  }
}

/// Simple semaphore to limit concurrency
class _Semaphore {
  _Semaphore(this._maxCount) : _count = _maxCount;
  final int _maxCount;
  int _count;
  final _waiters = <Completer<void>>[];

  Future<void> acquire() async {
    if (_count > 0) {
      _count--;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      final next = _waiters.removeAt(0);
      next.complete();
    } else {
      _count++;
    }
  }
}
