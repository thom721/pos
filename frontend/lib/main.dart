import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:pos_connect/app.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/services/local_db_service.dart';

void main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  // Désactiver le fetching réseau Google Fonts partout — toutes les pages
  // utilisent désormais TextStyle (police système) au lieu de GoogleFonts.inter()
  GoogleFonts.config.allowRuntimeFetching = false;

  await initializeDateFormatting('fr');
  await initServerUrl();
  await LocalDbService.instance.init();

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    launchAtStartup.setup(
      appName: 'POS Connect',
      appPath: Platform.resolvedExecutable,
    );
  }

  runApp(const ProviderScope(child: PosApp()));
}
