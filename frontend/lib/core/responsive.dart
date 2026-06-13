import 'package:flutter/material.dart';

abstract class AppBreakpoints {
  static const double sm = 360;   // petits téléphones
  static const double md = 480;   // téléphones standards
  static const double lg = 720;   // grandes tablettes / desktop
  static const double xl = 1100;  // large desktop
}

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// Vrai sur tout écran < 720 px (téléphone)
  bool get isMobile => screenWidth < AppBreakpoints.lg;

  /// Vrai si < 480 px (petit téléphone)
  bool get isSmallPhone => screenWidth < AppBreakpoints.md;

  /// Vrai si < 360 px (très petit téléphone)
  bool get isTinyPhone => screenWidth < AppBreakpoints.sm;

  bool get isTablet =>
      screenWidth >= AppBreakpoints.lg && screenWidth < AppBreakpoints.xl;

  bool get isDesktop => screenWidth >= AppBreakpoints.xl;

  /// Padding horizontal adapté à la taille d'écran
  double get hPad => isTinyPhone ? 12.0 : (isMobile ? 16.0 : 24.0);

  /// EdgeInsets symétrique horizontal adapté
  EdgeInsets get hPadding => EdgeInsets.symmetric(horizontal: hPad);

  /// EdgeInsets tout autour adapté
  EdgeInsets get pagePadding => EdgeInsets.all(hPad);
}
