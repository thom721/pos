import 'package:dio/dio.dart';

void configureLocalHttps(Dio dio, String serverIp) {}
void resetLocalHttps(Dio dio) {}

Future<bool> tryAutoDiscoverLocalServer(
        {int port = 443, Duration timeout = const Duration(seconds: 3)}) =>
    Future.value(false);
void configureAutoDiscoveredHttps(Dio dio, {int port = 443}) {}
Future<void> tryAddHostsEntry(String ip) => Future.value();
