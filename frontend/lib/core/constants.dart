class AppConstants {
  // IP du serveur sur le réseau local.
  // Pour l'émulateur Android, remplacer par '10.0.2.2'.
  static const _serverIp = '192.168.0.104';

  static String get baseUrl => 'http://$_serverIp:8002';

  static const tokenKey = 'access_token';
  static const userKey = 'user_data';
  static const serverUrlKey = 'server_url';
  static const appName = 'POS Connect';
}
