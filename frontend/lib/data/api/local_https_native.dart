import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

const _localHost = 'infini-post.local';

// Empreinte SHA-256 du certificat server.crt bundlé avec l'installateur
// Windows — le même certificat auto-signé pour toutes les installations
// (voir certificat/server.crt). Épinglage réel : le certificat présenté
// doit correspondre EXACTEMENT à celui-ci, pas juste avoir le bon nom
// d'hôte — sinon n'importe quel certificat (attaquant compris) serait
// accepté pour "infini-post.local".
//
// À recalculer si server.crt est régénéré :
//   openssl x509 -in certificat/server.crt -noout -fingerprint -sha256
const _pinnedCertSha256 =
    '8185f919d15cb09cdd520fefaa68b962f90686aa33b450edcd883e5a607068ac';

String _sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

bool _acceptPinnedCert(X509Certificate cert, String host, int port) {
  if (host != _localHost) return false;
  return _sha256Hex(cert.der) == _pinnedCertSha256;
}

void configureLocalHttps(Dio dio, String serverIp) {
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => HttpClient()
      ..badCertificateCallback = _acceptPinnedCert
      ..connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) {
        // Résout infini-post.local → IP du serveur au niveau socket
        // TLS utilise toujours "infini-post.local" comme SNI hostname
        final target = uri.host == _localHost ? serverIp : uri.host;
        return Socket.startConnect(target, uri.port);
      },
  );
}

void resetLocalHttps(Dio dio) {
  dio.httpClientAdapter = IOHttpClientAdapter();
}

/// Tente une connexion à "infini-post.local" en laissant le SYSTÈME
/// (résolveur DNS/mDNS de l'OS — Windows 10+/macOS/Linux savent tous
/// résoudre les noms .local nativement, voir api/services/mdns_service.py
/// côté serveur) trouver l'IP, plutôt que de la faire saisir manuellement.
/// Si ça répond, aucune adresse IP n'est nécessaire — l'auto-découverte a
/// fonctionné. Timeout court : sur un réseau qui bloque le multicast
/// (pare-feu, VPN, certaines configs d'entreprise), on veut échouer vite
/// pour retomber sur la saisie manuelle plutôt que de bloquer l'UI.
Future<bool> tryAutoDiscoverLocalServer(
    {int port = 443, Duration timeout = const Duration(seconds: 3)}) async {
  final client = HttpClient()..badCertificateCallback = _acceptPinnedCert;
  try {
    final portSuffix = port == 443 ? '' : ':$port';
    final uri = Uri.parse('https://$_localHost$portSuffix/api/setup/health');
    final req = await client.getUrl(uri).timeout(timeout);
    final res = await req.close().timeout(timeout);
    await res.drain<void>();
    return res.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

/// Configure Dio pour utiliser "infini-post.local" directement, résolu à
/// CHAQUE requête par le système (mDNS) — contrairement à
/// configureLocalHttps(), aucune IP fixe n'est mémorisée : si le serveur
/// change d'adresse (autre DHCP, autre réseau), ça continue de fonctionner
/// sans reconfiguration, tant que mDNS reste disponible sur ce réseau.
void configureAutoDiscoveredHttps(Dio dio, {int port = 443}) {
  final portSuffix = port == 443 ? '' : ':$port';
  dio.options.baseUrl = 'https://$_localHost$portSuffix';
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => HttpClient()
      ..badCertificateCallback = _acceptPinnedCert,
  );
}

/// Best-effort : ajoute/met à jour l'entrée "infini-post.local" dans le
/// fichier hosts de CETTE machine cliente avec l'IP saisie manuellement
/// (repli utilisé quand mDNS échoue sur ce réseau). Rend "infini-post.local"
/// résoluble par TOUT logiciel sur cette machine (navigateur, curl...), pas
/// seulement par cette app — contrairement au contournement socket de
/// configureLocalHttps(), qui lui fonctionne déjà sans ceci et ne dépend
/// donc jamais du succès de cette écriture.
///
/// Nécessite des droits administrateur sur Windows (C:\Windows\System32\...).
/// Échoue silencieusement sinon — l'app reste 100% fonctionnelle via le
/// contournement socket qui ne demande, lui, aucun droit particulier.
Future<void> tryAddHostsEntry(String ip) async {
  try {
    final hostsPath = Platform.isWindows
        ? r'C:\Windows\System32\drivers\etc\hosts'
        : '/etc/hosts';
    final file = File(hostsPath);
    if (!await file.exists()) return;
    final lines = await file.readAsLines();
    if (lines.any((l) => !l.trim().startsWith('#') &&
        l.contains(_localHost) && l.contains(ip))) {
      return; // déjà à jour avec cette IP exacte
    }
    final kept = lines.where((l) => !l.contains(_localHost)).toList()
      ..add('$ip\t$_localHost');
    await file.writeAsString('${kept.join('\n')}\n');
  } catch (_) {
    // Pas de droits admin (UAC requis) ou autre erreur — non bloquant.
  }
}
