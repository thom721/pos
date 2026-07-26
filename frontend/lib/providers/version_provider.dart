import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/services/version_check_service.dart';

final versionProvider = FutureProvider<VersionStatus>((ref) async {
  return VersionCheckService.check();
});
