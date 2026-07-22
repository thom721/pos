import 'package:flutter/material.dart';

class PosLogo extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icon/splash_logo.png',
      width: width,
      height: height,
      fit: fit,
    );
  }
}
