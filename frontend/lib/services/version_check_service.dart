import 'package:dio/dio.dart';
import 'package:pos_connect/core/constants.dart';

enum VersionUpdateType { none, optional, forced }

class VersionStatus {
  final VersionUpdateType updateType;
  final String latestVersion;
  final int latestBuild;
  final String? updateNotes;
  final String? updateUrl;

  const VersionStatus({
    required this.updateType,
    required this.latestVersion,
    required this.latestBuild,
    this.updateNotes,
    this.updateUrl,
  });

  bool get hasUpdate => updateType != VersionUpdateType.none;
  bool get isForced  => updateType == VersionUpdateType.forced;
}

class VersionCheckService {
  static Future<VersionStatus> check() async {
    try {
      final client = Dio(BaseOptions(
        baseUrl: AppConstants.cloudUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ));
      final res  = await client.get('/api/public/version');
      final data = res.data as Map<String, dynamic>;

      final latestBuild   = (data['latest_build']   as num?)?.toInt() ?? 1;
      final latestVersion = data['latest_version']  as String? ?? '0.9.0';
      final updateNotes   = data['update_notes']    as String?;
      final updateUrl     = data['update_url']      as String?;
      final forceUpdate   = data['force_update']    as bool? ?? false;

      final hasUpdate = AppConstants.appBuildNumber < latestBuild;

      return VersionStatus(
        updateType: !hasUpdate
            ? VersionUpdateType.none
            : forceUpdate
                ? VersionUpdateType.forced
                : VersionUpdateType.optional,
        latestVersion: latestVersion,
        latestBuild:   latestBuild,
        updateNotes:   updateNotes,
        updateUrl:     updateUrl,
      );
    } catch (_) {
      return const VersionStatus(
        updateType:    VersionUpdateType.none,
        latestVersion: AppConstants.appVersion,
        latestBuild:   AppConstants.appBuildNumber,
      );
    }
  }
}
