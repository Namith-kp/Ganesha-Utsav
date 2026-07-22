import '../utils/platform_io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/panorama_download_service.dart';

export '../services/panorama_download_service.dart' show DownloadProgress;

// ── Is the one-time download already complete? ─────────────────────────────
final panoramaDownloadCompleteProvider = FutureProvider<bool>((ref) async {
  return PanoramaDownloadService.isDownloadComplete;
});

// ── Local file path for a given panorama ID ────────────────────────────────
final localPanoramaFileProvider = FutureProvider.family<File?, String>((
  ref,
  panoid,
) async {
  return PanoramaDownloadService.localFileFor(panoid);
});

// ── Download progress stream ───────────────────────────────────────────────
final downloadProgressProvider = StreamProvider<DownloadProgress>((ref) {
  return PanoramaDownloadService().downloadAll();
});
