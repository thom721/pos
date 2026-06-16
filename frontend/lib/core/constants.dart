class AppConstants {
  // ── Server URL — configurable at compile time via --dart-define ────────
  // flutter build web --release \
  //   --dart-define=SERVER_SCHEME=https \
  //   --dart-define=SERVER_IP=api.posconnect.ht \
  //   --dart-define=SERVER_PORT=443
  static const _serverScheme =
      String.fromEnvironment('SERVER_SCHEME', defaultValue: 'http');
  static const _serverIp =
      String.fromEnvironment('SERVER_IP', defaultValue: '192.168.0.104');
  static const _serverPort =
      String.fromEnvironment('SERVER_PORT', defaultValue: '8002');
  static String get baseUrl => '$_serverScheme://$_serverIp:$_serverPort';

  // ── Cloud SaaS URL (wizard + identity check) ───────────────────────────
  static const cloudUrl = String.fromEnvironment(
    'CLOUD_URL',
    defaultValue: 'http://192.168.0.104:8002',
  );

  // ── Server identity — Ed25519 public key (base64 raw, 32 bytes) ───────
  // Corresponds to IDENTITY_PRIVATE_KEY on the cloud server.
  // DO NOT change without regenerating the key pair on the server.
  static const identityPublicKeyB64 =
      'xH5c/Vb6SAyFKRPpmGw2Yuzetv/h2G9KYtO+ya59fzA=';

  // ── SharedPreferences keys ─────────────────────────────────────────────
  static const tokenKey = 'access_token';
  static const userKey = 'user_data';
  static const serverUrlKey = 'server_url';
  static const connectionModeKey = 'connection_mode'; // 'cloud' | 'local'
  static const deviceIdKey = 'device_id';
  static const tenantKey = 'tenant_data';

  static const appName = 'POS Connect';
}
