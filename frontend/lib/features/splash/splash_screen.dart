import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_connect/core/constants.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    FlutterNativeSplash.remove();

    if (kIsWeb) {
      // Web: attendre que authProvider finisse d'initialiser (lecture storage),
      // puis naviguer selon l'état réel — évite la course avec le redirect router.
      while (ref.read(authProvider).isLoading) {
        await Future.delayed(const Duration(milliseconds: 30));
        if (!mounted) return;
      }
      if (!mounted) return;
      if (ref.read(authProvider).isAuthenticated) {
        context.go('/dashboard');
        return;
      }
      // Non authentifié — vérifier si le setup serveur est nécessaire
      try {
        final res = await dio
            .get('/api/setup/health')
            .timeout(const Duration(seconds: 4));
        if (!mounted) return;
        final setupDone = res.data['setup_done'] as bool? ?? true;
        if (!setupDone) {
          context.go('/install');
          return;
        }
      } catch (_) {}
      if (!mounted) return;
      context.go('/home');
      return;
    }

    // Non-web (mobile / desktop) : navigation directe, pas d'animation.
    final prefs = await SharedPreferences.getInstance();
    final isMobile = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;

    if (isMobile) {
      await prefs.setBool(AppConstants.clientSetupDoneKey, true);
    } else {
      final localSetupDone =
          prefs.getBool(AppConstants.clientSetupDoneKey) ?? false;
      if (!mounted) return;
      if (!localSetupDone) {
        context.go('/install');
        return;
      }
    }

    if (!mounted) return;
    context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(backgroundColor: Color(0xFF1B2A3B));
  }
}
