import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, SystemSound, SystemSoundType;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pos_connect/core/theme.dart';

// Le scan caméra (mobile_scanner) ne supporte pas Windows/Linux — sur ces
// plateformes, seule la douchette USB/Bluetooth (HID → clavier + Entrée)
// reste disponible.
bool get cameraScanSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// Certains décodeurs caméra préfixent la valeur brute par l'identifiant de
/// symbologie AIM (ISO/IEC 15424) — ex: "]C1" pour Code128, "]E0" pour
/// EAN-13. Purement technique, absent du code-barres réellement imprimé.
final _aimSymbologyPrefix = RegExp(r'^\][A-Za-z]\d');

String stripAimSymbologyPrefix(String code) =>
    code.replaceFirst(_aimSymbologyPrefix, '');

/// Plein écran caméra pour le scan de codes-barres.
///
/// - [continuous] = true (défaut, ex. panier caisse) : l'écran reste ouvert
///   après chaque code détecté, [onCode] gère l'effet de bord (ex. ajout au
///   panier) et renvoie un message d'erreur ou null — la caméra continue de
///   scanner jusqu'à fermeture manuelle.
/// - [continuous] = false (ex. remplir un champ code-barres) : dès le
///   premier code détecté, [onCode] est appelé puis l'écran se referme tout
///   seul (retourne le code scanné via [Navigator.pop]).
class BarcodeScannerSheet extends StatefulWidget {
  final Future<String?> Function(String code) onCode;
  final bool continuous;

  const BarcodeScannerSheet({
    super.key,
    required this.onCode,
    this.continuous = true,
  });

  @override
  State<BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<BarcodeScannerSheet> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
  );
  String? _lastCode;
  DateTime? _lastAt;
  String? _feedback;
  bool _feedbackOk = true;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    final barcodes = capture.barcodes;
    final rawCode = barcodes.isEmpty ? null : barcodes.first.rawValue;
    if (rawCode == null || rawCode.isEmpty || _busy) return;
    final code = stripAimSymbologyPrefix(rawCode);
    if (code.isEmpty) return;

    // Anti-rebond : ignore la relecture du même code pendant 1.5s
    // (la caméra détecte le même code plusieurs fois par seconde).
    final now = DateTime.now();
    if (code == _lastCode &&
        _lastAt != null &&
        now.difference(_lastAt!) < const Duration(milliseconds: 1500)) {
      return;
    }
    _lastCode = code;
    _lastAt = now;

    setState(() => _busy = true);
    final error = await widget.onCode(code);
    if (!mounted) return;

    // Bip + vibration au scan réussi — confirmation sans avoir à regarder
    // l'écran, comme une douchette physique. Vibration seule si erreur
    // (code inconnu) pour rester distinguable sans être une alarme.
    if (error == null) {
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.vibrate();
    }

    if (!widget.continuous) {
      Navigator.of(context).pop(code);
      return;
    }

    setState(() {
      _busy = false;
      _feedbackOk = error == null;
      _feedback = error ?? 'Ajouté au panier';
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scanner un code-barres'),
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, state, child) => Icon(
                state.torchState == TorchState.on
                    ? Icons.flash_on_rounded
                    : Icons.flash_off_rounded,
              ),
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _handleDetect),
          // Cadre de visée
          Center(
            child: Container(
              width: 260,
              height: 180,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (_feedback != null)
            Positioned(
              bottom: 32,
              left: 24,
              right: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: (_feedbackOk ? AppColors.success : AppColors.error)
                      .withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                        _feedbackOk
                            ? Icons.check_circle_rounded
                            : Icons.error_outline_rounded,
                        color: Colors.white),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(_feedback!,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
