import 'dart:io';

import 'package:darktar/config/env.dart';
import 'package:darktar/server.dart';

/// Darktar - A self-hosted private package registry for Dart and Flutter.
///
/// Entry point for the server application.
Future<void> main(List<String> arguments) async {
  // Load environment configuration
  final config = EnvConfig.fromEnvironment();

  // Print startup banner
  _printBanner(config);

  // Start the server
  final server = DarktarServer(config);
  await server.start();

  // Handle shutdown signals
  ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('\n🛑 Shutting down Darktar...');
    await server.stop();
    exit(0);
  });

  ProcessSignal.sigterm.watch().listen((_) async {
    await server.stop();
    exit(0);
  });
}

void _printBanner(EnvConfig config) {
  stdout.writeln('''
┌─────────────────────────────────────────┐
│                                         │
│   ██████╗  █████╗ ██████╗ ██╗  ██╗      │
│   ██╔══██╗██╔══██╗██╔══██╗██║ ██╔╝      │
│   ██║  ██║███████║██████╔╝█████╔╝       │
│   ██║  ██║██╔══██║██╔══██╗██╔═██╗       │
│   ██████╔╝██║  ██║██║  ██║██║  ██╗      │
│   ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝      │
│                     TAR                 │
│                                         │
│   Private Dart Package Registry         │
│   Version: 0.1.0                        │
│                                         │
└─────────────────────────────────────────┘

📦 Storage Path: ${config.storagePath}
🌐 Server URL:   http://${config.host}:${config.port}
''');
}
