import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:pos_connect/app.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/services/local_db_service.dart';

void main() async {
  // Maintient le splash natif visible jusqu'à FlutterNativeSplash.remove()
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  await initializeDateFormatting('fr');
  await initServerUrl();
  await LocalDbService.instance.init(); // ouvre / crée pos_cache.db

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    launchAtStartup.setup(
      appName: 'POS Connect',
      appPath: Platform.resolvedExecutable,
    );
  }

  runApp(const ProviderScope(child: PosApp()));
}
