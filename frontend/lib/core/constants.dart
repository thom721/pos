class AppConstants {
  // ── Local server (default for local-mode deployments) ──────────────────
  static const _serverIp = '192.168.0.104';
  static String get baseUrl => 'http://$_serverIp:8002';

  // ── Cloud SaaS URL ─────────────────────────────────────────────────────
  // Change this to the production VPS URL before deploying.
  static const cloudUrl =
      'http://192.168.0.104:8002'; // TODO: replace with VPS URL

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
