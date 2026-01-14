import 'dart:io';

/// Environment configuration for Darktar server.
///
/// All configuration is read from environment variables following
/// the 12-factor app methodology.
class EnvConfig {
  const EnvConfig({
    required this.port,
    required this.host,
    required this.storagePath,
    required this.adminToken,
    required this.databasePath,
    required this.docsPath,
    this.baseUrl,
  });

  /// The port to listen on.
  final int port;

  /// The host to bind to.
  final String host;

  /// Path to store package tarballs.
  final String storagePath;

  /// Admin token for privileged operations.
  final String adminToken;

  /// Path to the SQLite database file.
  final String databasePath;

  /// Path to store generated documentation.
  final String docsPath;

  /// Optional base URL for the server (used in API responses).
  final String? baseUrl;

  /// Creates configuration from environment variables.
  factory EnvConfig.fromEnvironment() {
    final port = int.tryParse(
          Platform.environment['DARKTAR_PORT'] ?? '8080',
        ) ??
        8080;

    final host = Platform.environment['DARKTAR_HOST'] ?? '0.0.0.0';

    final storagePath =
        Platform.environment['DARKTAR_STORAGE_PATH'] ?? './data/storage';

    final adminToken =
        Platform.environment['DARKTAR_ADMIN_TOKEN'] ?? _generateDefaultToken();

    final databasePath =
        Platform.environment['DARKTAR_DATABASE_PATH'] ?? './data/darktar.db';

    final docsPath =
        Platform.environment['DARKTAR_DOCS_PATH'] ?? './data/docs';

    final baseUrl = Platform.environment['DARKTAR_BASE_URL'];

    return EnvConfig(
      port: port,
      host: host,
      storagePath: storagePath,
      adminToken: adminToken,
      databasePath: databasePath,
      docsPath: docsPath,
      baseUrl: baseUrl,
    );
  }

  /// Generates a default admin token (for development only).
  static String _generateDefaultToken() {
    stderr.writeln(
      '⚠️  WARNING: Using default admin token. '
      'Set DARKTAR_ADMIN_TOKEN in production!',
    );
    return 'darktar-dev-token';
  }

  /// Returns the effective base URL for this server.
  String get effectiveBaseUrl => baseUrl ?? 'http://$host:$port';
}

