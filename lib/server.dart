import 'dart:io';

import 'package:darktar/api/handlers/admin.dart';
import 'package:darktar/api/handlers/auth.dart';
import 'package:darktar/api/handlers/packages.dart';
import 'package:darktar/api/middleware/auth.dart';
import 'package:darktar/config/env.dart';
import 'package:darktar/data/database.dart';
import 'package:darktar/jobs/job_queue.dart';
import 'package:darktar/storage/blob_storage.dart';
import 'package:darktar/storage/file_system_storage.dart';
import 'package:darktar/web/handlers/admin_pages.dart';
import 'package:darktar/web/handlers/pages.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

/// The main Darktar server.
///
/// Handles HTTP requests for the Pub API and Web UI.
class DarktarServer {
  DarktarServer(this.config);

  final EnvConfig config;
  HttpServer? _server;
  late final DarktarDatabase _db;
  late final BlobStorage _storage;
  late final JobQueue _jobQueue;

  /// Starts the HTTP server.
  Future<void> start() async {
    // Initialize database
    _db = DarktarDatabase.fromPath(config.databasePath);

    // Initialize storage
    _storage = FileSystemStorage(config.storagePath);

    // Initialize job queue
    _jobQueue = JobQueue();
    _setupJobLogging();

    // Ensure directories exist
    await Directory(config.storagePath).create(recursive: true);
    await Directory(config.docsPath).create(recursive: true);

    // Build handlers
    final authHandlers = AuthHandlers(db: _db);
    final adminHandlers = AdminHandlers(db: _db);

    final packageHandlers = PackageHandlers(
      db: _db,
      storage: _storage,
      config: config,
      jobQueue: _jobQueue,
    );

    final pageHandlers = PageHandlers(
      db: _db,
      config: config,
      templateDir: _getTemplateDir(),
    );

    final adminPageHandlers = AdminPageHandlers(
      db: _db,
      config: config,
      templateDir: _getTemplateDir(),
    );

    final router = _buildRouter(
      authHandlers,
      adminHandlers,
      packageHandlers,
      pageHandlers,
      adminPageHandlers,
    );

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addMiddleware(authMiddleware(_db))
        .addHandler(router.call);

    _server = await shelf_io.serve(
      handler,
      config.host,
      config.port,
    );

    stdout.writeln(
      '✅ Darktar is running on http://${config.host}:${config.port}',
    );
  }

  /// Stops the HTTP server.
  Future<void> stop() async {
    await _jobQueue.shutdown();
    await _server?.close(force: true);
    await _db.close();
    stdout.writeln('👋 Darktar stopped.');
  }

  /// Sets up logging for job events.
  void _setupJobLogging() {
    _jobQueue.events.listen((event) {
      switch (event) {
        case JobEnqueued():
          stdout.writeln('📋 Job enqueued: ${event.job}');
        case JobStarted():
          stdout.writeln('▶️  Job started: ${event.job}');
        case JobCompleted():
          stdout.writeln('✅ Job completed: ${event.job}');
        case JobFailed():
          stderr.writeln('❌ Job failed: ${event.job} - ${event.error}');
      }
    });
  }

  /// Builds the main router with all routes.
  Router _buildRouter(
    AuthHandlers authHandlers,
    AdminHandlers adminHandlers,
    PackageHandlers packageHandlers,
    PageHandlers pageHandlers,
    AdminPageHandlers adminPageHandlers,
  ) {
    final router = Router();

    // Health check endpoint
    router.get('/health', _healthHandler);

    // Register API routes
    authHandlers.registerRoutes(router);
    packageHandlers.registerRoutes(router);

    // Register Admin API routes with admin middleware protection
    final adminRouter = Router();
    adminHandlers.registerRoutes(adminRouter);
    router.mount(
      '/api/admin',
      Pipeline().addMiddleware(requireAdmin()).addHandler(adminRouter.call),
    );

    // Register Admin Page routes with admin middleware protection
    final adminPageRouter = Router();
    adminPageHandlers.registerRoutes(adminPageRouter);
    router.mount(
      '/admin',
      Pipeline().addMiddleware(requireAdmin()).addHandler(adminPageRouter.call),
    );

    // Register Web UI routes
    pageHandlers.registerRoutes(router);

    // Static file serving
    final staticHandler = createStaticHandler(
      _getStaticDir(),
      defaultDocument: 'index.html',
    );
    router.mount('/static/', staticHandler);

    // Documentation serving (generated docs)
    final docsDir = _getDocsDir();
    if (Directory(docsDir).existsSync()) {
      final docsHandler = createStaticHandler(
        docsDir,
        defaultDocument: 'index.html',
      );
      router.mount('/docs/', docsHandler);
    }

    // Catch-all for 404
    router.all('/<ignored|.*>', _notFoundHandler);

    return router;
  }

  /// Health check handler.
  Response _healthHandler(Request request) {
    return Response.ok(
      '{"status":"ok","version":"0.1.0","timestamp":"${DateTime.now().toUtc().toIso8601String()}","jobs":{"pending":${_jobQueue.pendingCount},"running":${_jobQueue.runningCount}}}',
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// 404 handler.
  Response _notFoundHandler(Request request) {
    // Return JSON for API requests, HTML for browser
    final acceptsHtml =
        request.headers['accept']?.contains('text/html') ?? false;

    if (acceptsHtml) {
      return Response.notFound(
        '''
<!DOCTYPE html>
<html>
<head><title>404 - Not Found</title></head>
<body style="font-family: sans-serif; background: #0f172a; color: #f8fafc; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0;">
  <div style="text-align: center;">
    <h1 style="font-size: 6rem; margin: 0;">404</h1>
    <p>Page not found</p>
    <a href="/" style="color: #38bdf8;">← Back to home</a>
  </div>
</body>
</html>
''',
        headers: {'Content-Type': 'text/html'},
      );
    }

    return Response.notFound(
      '{"error":"Not found"}',
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// CORS middleware for development.
  Middleware _corsMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok(
            '',
            headers: _corsHeaders,
          );
        }

        final response = await innerHandler(request);
        return response.change(headers: _corsHeaders);
      };
    };
  }

  static const _corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization',
  };

  /// Gets the template directory path.
  String _getTemplateDir() {
    const devPath = 'lib/web/templates';
    const prodPath = '/app/templates';

    if (Directory(prodPath).existsSync()) {
      return prodPath;
    }
    return devPath;
  }

  /// Gets the static files directory path.
  String _getStaticDir() {
    const devPath = 'lib/web/static';
    const prodPath = '/app/static';

    if (Directory(prodPath).existsSync()) {
      return prodPath;
    }
    return devPath;
  }

  /// Gets the generated docs directory path.
  String _getDocsDir() {
    if (Directory('/app/docs').existsSync()) {
      return '/app/docs';
    }
    return config.docsPath;
  }
}
