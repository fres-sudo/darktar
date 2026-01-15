import 'dart:io';

import 'package:darktar/config/env.dart';
import 'package:darktar/data/database.dart';
import 'package:darktar/data/repositories/package_repository.dart';
import 'package:darktar/data/repositories/version_repository.dart';
import 'package:darktar/data/result.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:mustache_template/mustache_template.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:yaml/yaml.dart';

/// Handlers for the Web UI pages.
class PageHandlers {
  PageHandlers({
    required this.db,
    required this.config,
    required this.templateDir,
  })  : packageRepository = PackageRepository(db),
        versionRepository = VersionRepository(db);

  final DarktarDatabase db;
  final EnvConfig config;
  final String templateDir;
  final PackageRepository packageRepository;
  final VersionRepository versionRepository;

  // Template cache
  Template? _layoutTemplate;
  Template? _homeTemplate;
  Template? _packageTemplate;
  Template? _authTemplate;

  /// Registers routes on the provided router.
  void registerRoutes(Router router) {
    router.get('/', homePage);
    router.get('/packages/<name>', packagePage);
    router.get('/auth', authPage);
  }

  /// Home page with package listing.
  Future<Response> homePage(Request request) async {
    final query = request.url.queryParameters['q'];

    final packagesResult = await packageRepository.listAll(
      limit: 50,
      searchQuery: query,
    );

    switch (packagesResult) {
      case Ok(value: final packages):
        // Get latest version for each package
        final packageData = <Map<String, dynamic>>[];
        for (final pkg in packages) {
          final latestResult = await versionRepository.getLatest(pkg.id);
          final latestVersion = switch (latestResult) {
            Ok(value: final v) => v.version,
            Error() => '0.0.0',
          };

          packageData.add({
            'name': pkg.name,
            'description': pkg.description ?? 'No description provided',
            'latestVersion': latestVersion,
            'publishedAt': _formatDate(pkg.createdAt),
          });
        }

        final content = await _renderTemplate('home', {
          'query': query ?? '',
          'hasQuery': query != null && query.isNotEmpty,
          'packages': packageData,
          'hasPackages': packageData.isNotEmpty,
          'packageCount': packageData.length,
          'hasMultiple': packageData.length != 1,
          'baseUrl': config.effectiveBaseUrl,
        });

        return _renderPage(
          title: query != null ? 'Search: $query' : 'Packages',
          description: 'Browse private Dart packages',
          content: content,
        );

      case Error():
        return Response.internalServerError(body: 'Failed to load packages');
    }
  }

  /// Package detail page.
  Future<Response> packagePage(Request request, String name) async {
    final packageResult = await packageRepository.getByName(name);

    switch (packageResult) {
      case Ok(value: final package):
        final versionsResult =
            await versionRepository.listForPackage(package.id);

        switch (versionsResult) {
          case Ok(value: final versions):
            if (versions.isEmpty) {
              return Response.notFound('Package has no versions');
            }

            final latest = versions.first;
            final pubspec = _parsePubspec(latest.pubspecYaml);

            final versionData = versions
                .map(
                  (v) => {
                    'packageName': package.name,
                    'version': v.version,
                    'publishedAt': _formatDate(v.createdAt),
                    'isLatest': v.id == latest.id,
                    'isRetracted': v.isRetracted,
                  },
                )
                .toList();

            final content = await _renderTemplate('package', {
              'name': package.name,
              'description': package.description ?? 'No description provided',
              'latestVersion': latest.version,
              'isDiscontinued': package.isDiscontinued,
              'baseUrl': config.effectiveBaseUrl,
              'versions': versionData,
              'hasReadme': latest.readme != null,
              'readmeHtml':
                  latest.readme != null ? _renderMarkdown(latest.readme!) : '',
              'hasChangelog': latest.changelog != null,
              'changelogHtml': latest.changelog != null
                  ? _renderMarkdown(latest.changelog!)
                  : '',
              'publishedAt': _formatDate(latest.createdAt),
              'sdkConstraint': pubspec['environment']?['sdk'] ?? 'any',
              'homepage': pubspec['homepage'],
              'repository': pubspec['repository'],
              'issueTracker': pubspec['issue_tracker'],
              'license': pubspec['license'],
            });

            return _renderPage(
              title: package.name,
              description: package.description ?? 'Dart package',
              content: content,
            );

          case Error():
            return Response.internalServerError(
                body: 'Failed to load versions');
        }

      case Error():
        return Response.notFound('Package not found: $name');
    }
  }

  // ===========================================================================
  // Private helpers
  // ===========================================================================

  /// Renders a template with the given data.
  Future<String> _renderTemplate(String name, Map<String, dynamic> data) async {
    Template? template;

    switch (name) {
      case 'home':
        template = _homeTemplate ??= await _loadTemplate('home.html');
      case 'package':
        template = _packageTemplate ??= await _loadTemplate('package.html');
      case 'auth':
        template = _authTemplate ??= await _loadTemplate('auth.html');
    }

    return template?.renderString(data) ?? '';
  }

  /// Auth page for token generation.
  Future<Response> authPage(Request request) async {
    final content = await _renderTemplate('auth', {
      'baseUrl': config.effectiveBaseUrl,
    });

    return _renderPage(
      title: 'Get Started',
      description: 'Generate a token to publish and consume private packages',
      content: content,
    );
  }

  /// Renders a full page with layout.
  Future<Response> _renderPage({
    required String title,
    required String description,
    required String content,
  }) async {
    _layoutTemplate ??= await _loadTemplate('layout.html');

    final html = _layoutTemplate!.renderString({
      'title': title,
      'description': description,
      'content': content,
      'version': '0.1.0',
    });

    return Response.ok(
      html,
      headers: {'Content-Type': 'text/html; charset=utf-8'},
    );
  }

  /// Loads a template from disk.
  Future<Template> _loadTemplate(String filename) async {
    final file = File('$templateDir/$filename');
    final source = await file.readAsString();
    return Template(source, htmlEscapeValues: false);
  }

  /// Parses pubspec YAML.
  Map<String, dynamic> _parsePubspec(String yaml) {
    try {
      final doc = loadYaml(yaml);
      return Map<String, dynamic>.from(doc as Map);
    } catch (_) {
      return {};
    }
  }

  /// Renders markdown to HTML.
  String _renderMarkdown(String markdown) {
    return md.markdownToHtml(
      markdown,
      extensionSet: md.ExtensionSet.gitHubWeb,
    );
  }

  /// Formats a date for display.
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }
    if (diff.inDays < 30) {
      return '${(diff.inDays / 7).floor()}w ago';
    }
    if (diff.inDays < 365) {
      return '${(diff.inDays / 30).floor()}mo ago';
    }
    return '${(diff.inDays / 365).floor()}y ago';
  }
}
