import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

class UpdateService {
  static const String repoOwner = 'Namith-kp';
  static const String repoName = 'Ganesha-funds-tracker';

  /// Checks if a new version is available on GitHub Releases
  /// Returns the download URL if an update is available, null otherwise.
  static Future<String?> checkForUpdate() async {
    if (kIsWeb) return null; // No in-app updates for Web

    try {
      final dio = Dio();
      final response = await dio.get(
        'https://api.github.com/repos/$repoOwner/$repoName/releases/latest',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final String tag = data['tag_name'] ?? '';
        // Tag format expected: v1.0.0+2
        final latestVersionString = tag.startsWith('v') ? tag.substring(1) : tag;

        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersionString = '${packageInfo.version}+${packageInfo.buildNumber}';

        if (_isNewerVersion(latestVersionString, currentVersionString)) {
          final assets = data['assets'] as List;
          final apkAsset = assets.firstWhere(
            (asset) => asset['name'].toString().endsWith('.apk'),
            orElse: () => null,
          );

          if (apkAsset != null) {
            return apkAsset['browser_download_url'];
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking for updates: $e');
    }
    return null;
  }

  /// Downloads the APK and triggers installation
  static Future<void> downloadAndInstall(
      String url, Function(double) onProgress) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final savePath = '${tempDir.path}/update.apk';
      final dio = Dio();

      await dio.download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            onProgress(received / total);
          }
        },
      );

      final result = await OpenFilex.open(savePath);
      if (result.type != ResultType.done) {
        debugPrint('Error opening APK: ${result.message}');
      }
    } catch (e) {
      debugPrint('Error downloading update: $e');
    }
  }

  /// Compare versions like 1.0.0+2
  static bool _isNewerVersion(String latest, String current) {
    try {
      // Split into [1.0.0, 2]
      final latestParts = latest.split('+');
      final currentParts = current.split('+');

      final latestBase = latestParts[0].split('.');
      final currentBase = currentParts[0].split('.');

      // Compare major, minor, patch
      for (int i = 0; i < 3; i++) {
        final l = int.parse(latestBase[i]);
        final c = int.parse(currentBase[i]);
        if (l > c) return true;
        if (l < c) return false;
      }

      // If base is same, compare build numbers
      if (latestParts.length > 1 && currentParts.length > 1) {
        final lBuild = int.parse(latestParts[1]);
        final cBuild = int.parse(currentParts[1]);
        return lBuild > cBuild;
      }

      return false; // same version or couldn't parse build number
    } catch (e) {
      debugPrint('Error parsing versions: $e');
      return false;
    }
  }
}
