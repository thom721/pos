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

void configureLocalHttps(Dio dio, String serverIp) {
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        if (host != _localHost) return false;
        return _sha256Hex(cert.der) == _pinnedCertSha256;
      }
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
