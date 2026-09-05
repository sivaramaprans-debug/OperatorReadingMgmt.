import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../database/supabase_client.dart';

class AppUpdateInfo {
  final String latestVersion;
  final String apkUrl;
  final String releaseNotes;
  final bool hasUpdate;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.apkUrl,
    required this.releaseNotes,
    required this.hasUpdate,
  });
}

class AppUpdateService {
  static const String currentVersion = '1.5.6';
  static const String _githubApiUrl =
      'https://api.github.com/repos/sivaramaprans-debug/OperatorReadingMgmt./releases/latest';

  Future<AppUpdateInfo?> checkForUpdates() async {
    // 1. Try checking GitHub Releases directly
    try {
      final client = HttpClient();
      final uri = Uri.parse(_githubApiUrl);
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'OperatorReadingMgmtApp');
      final res = await req.close().timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final bodyStr = await res.transform(utf8.decoder).join();
        final json = jsonDecode(bodyStr) as Map<String, dynamic>;
        final tagName = (json['tag_name'] as String? ?? '').replaceAll('v', '').trim();
        final releaseNotes = (json['body'] as String? ?? 'New version available with improvements.').trim();
        final assets = json['assets'] as List? ?? [];
        final apkAsset = assets.firstWhere(
          (a) => (a['name'] as String? ?? '').endsWith('.apk'),
          orElse: () => null,
        );
        final downloadUrl = apkAsset != null
            ? (apkAsset['browser_download_url'] as String? ?? '')
            : (json['html_url'] as String? ?? '');

        client.close();

        if (tagName.isNotEmpty) {
          final hasUpdate = _isVersionHigher(tagName, currentVersion);
          return AppUpdateInfo(
            latestVersion: tagName,
            apkUrl: downloadUrl.isNotEmpty ? downloadUrl : 'https://github.com/sivaramaprans-debug/OperatorReadingMgmt./releases/latest',
            releaseNotes: releaseNotes,
            hasUpdate: hasUpdate,
          );
        }
      }
      client.close();
    } catch (e) {
      debugPrint('GitHub update check exception: $e');
    }

    // 2. Fallback to Supabase system_settings
    try {
      final response = await supabase
          .from('system_settings')
          .select('key, value');

      final Map<String, String> settings = {};
      for (final row in response) {
        settings[row['key'] as String] = (row['value'] ?? '') as String;
      }

      final latestVersion = settings['latest_app_version'] ?? '1.5.0';
      final rawApkUrl = settings['apk_download_url'] ?? '';
      final apkUrl = rawApkUrl.isNotEmpty
          ? rawApkUrl
          : 'https://github.com/sivaramaprans-debug/OperatorReadingMgmt./releases/latest';
      final releaseNotes = settings['app_release_notes'] ?? 'General performance improvements and bug fixes.';

      final hasUpdate = _isVersionHigher(latestVersion, currentVersion);

      return AppUpdateInfo(
        latestVersion: latestVersion,
        apkUrl: apkUrl,
        releaseNotes: releaseNotes,
        hasUpdate: hasUpdate,
      );
    } catch (e) {
      debugPrint('App update check fallback error: $e');
      return null;
    }
  }

  bool _isVersionHigher(String latest, String current) {
    try {
      final latestParts = latest.split('.').map(int.parse).toList();
      final currentParts = current.split('.').map(int.parse).toList();

      for (int i = 0; i < latestParts.length && i < currentParts.length; i++) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
      return latestParts.length > currentParts.length;
    } catch (_) {
      return false;
    }
  }

  Future<bool> launchApkDownload(String url) async {
    try {
      final uri = Uri.parse(url);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Launch APK error: $e');
      return false;
    }
  }
}

final appUpdateServiceProvider = Provider((ref) => AppUpdateService());

final appUpdateCheckProvider = FutureProvider<AppUpdateInfo?>((ref) async {
  final service = ref.watch(appUpdateServiceProvider);
  return service.checkForUpdates();
});
