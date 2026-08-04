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
  static const String currentVersion = '1.0.0';

  Future<AppUpdateInfo?> checkForUpdates() async {
    try {
      final response = await supabase
          .from('system_settings')
          .select('key, value');

      final Map<String, String> settings = {};
      for (final row in response) {
        settings[row['key'] as String] = (row['value'] ?? '') as String;
      }

      final latestVersion = settings['latest_app_version'] ?? '1.0.0';
      final apkUrl = settings['apk_download_url'] ?? '';
      final releaseNotes = settings['app_release_notes'] ?? 'General performance improvements and bug fixes.';

      final hasUpdate = _isVersionHigher(latestVersion, currentVersion);

      return AppUpdateInfo(
        latestVersion: latestVersion,
        apkUrl: apkUrl,
        releaseNotes: releaseNotes,
        hasUpdate: hasUpdate,
      );
    } catch (e) {
      debugPrint('App update check error: $e');
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
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return false;
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
