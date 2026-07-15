import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

const _localHost = 'infini-post.local';

void configureLocalHttps(Dio dio, String serverIp) {
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        return host == _localHost;
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
