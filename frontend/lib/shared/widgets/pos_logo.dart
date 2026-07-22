import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/providers/brand_provider.dart';

/// Logo POS Connect.
/// Si `logo_url` est configuré dans platform_config → image réseau.
/// Sinon → asset local (assets/icon/splash_logo.png).
class PosLogo extends ConsumerWidget {
  final double width;
  final double? height;
  final BoxFit fit;

  const PosLogo({
    super.key,
    this.width = 160,
    this.height,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logoUrl = ref.watch(brandProvider).valueOrNull;
    if (logoUrl != null) {
      return Image.network(
        logoUrl,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _assetLogo(),
      );
    }
    return _assetLogo();
  }

  Widget _assetLogo() => Image.asset(
        'assets/icon/splash_logo.png',
        width: width,
        height: height,
        fit: fit,
      );
}
