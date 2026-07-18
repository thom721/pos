class AppConstants {
  // ── Server URL — configurable at compile time via --dart-define ────────
  // flutter build web --release \
  //   --dart-define=SERVER_SCHEME=https \
  //   --dart-define=SERVER_IP=pos.infini-software.cloud \
  //   --dart-define=SERVER_PORT=443
  static const _serverScheme =
      String.fromEnvironment('SERVER_SCHEME', defaultValue: 'https');
  static const _serverIp =
      String.fromEnvironment('SERVER_IP', defaultValue: 'pos.infini-software.cloud');
  static const _serverPort =
      String.fromEnvironment('SERVER_PORT', defaultValue: '443');
  static String get baseUrl => '$_serverScheme://$_serverIp:$_serverPort';

  // ── Cloud SaaS URL (wizard + identity check) ───────────────────────────
  static const cloudUrl = String.fromEnvironment(
    'CLOUD_URL',
    defaultValue: 'https://pos.infini-software.cloud',
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
  static const serverIpKey  = 'server_local_ip';
  static const connectionModeKey = 'connection_mode'; // 'cloud' | 'local'
  static const deviceIdKey = 'device_id';
  static const tenantKey = 'tenant_data';
  static const clientSetupDoneKey = 'client_setup_done';
  static const planWarningKey = 'plan_warning';

  static const appName = 'POS Connect';
}
