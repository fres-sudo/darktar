import 'dart:convert';
import 'dart:io';

import 'package:darktar/config/env.dart';
import 'package:darktar/data/database.dart';
import 'package:darktar/data/repositories/audit_log_repository.dart';
import 'package:darktar/data/repositories/package_repository.dart';
import 'package:darktar/data/repositories/package_uploader_repository.dart';
import 'package:darktar/data/repositories/user_repository.dart';
import 'package:darktar/data/repositories/version_repository.dart';
import 'package:darktar/data/result.dart';
import 'package:mustache_template/mustache_template.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// Handlers for admin web pages.
class AdminPageHandlers {
  AdminPageHandlers({
    required this.db,
    required this.config,
    required this.templateDir,
  })  : userRepository = UserRepository(db),
        packageRepository = PackageRepository(db),
        versionRepository = VersionRepository(db),
        packageUploaderRepository = PackageUploaderRepository(db),
        auditLogRepository = AuditLogRepository(db);

  final DarktarDatabase db;
  final EnvConfig config;
  final String templateDir;
  final UserRepository userRepository;
  final PackageRepository packageRepository;
  final VersionRepository versionRepository;
  final PackageUploaderRepository packageUploaderRepository;
  final AuditLogRepository auditLogRepository;

  /// Registers routes on the provided router.
  void registerRoutes(Router router) {
    router.get('/admin', dashboard);
    router.get('/admin/users', usersPage);
    router.get('/admin/packages', packagesPage);
  }

  /// GET /admin
  ///
  /// Admin dashboard with system statistics.
  Future<Response> dashboard(Request request) async {
    // Get system statistics
    final packagesCountResult = await packageRepository.count();
    final packagesCount = switch (packagesCountResult) {
      Ok(value: final c) => c,
      Error() => 0,
    };

    final usersResult = await userRepository.listAll();
    final users = switch (usersResult) {
      Ok(value: final u) => u,
      Error() => <User>[],
    };

    final activeUsersCount = users.where((u) => u.status == 'active').length;
    final adminUsersCount = users
        .where((u) => u.isAdmin || u.role == 'admin' || u.role == 'super_admin')
        .length;

    // Get recent audit logs
    final logsResult = await auditLogRepository.list(limit: 10);
    final recentLogs = switch (logsResult) {
      Ok(value: final logs) => logs,
      Error() => <AuditLog>[],
    };

    // Render template
    final html = _renderTemplate('dashboard.html', {
      'title': 'Admin Dashboard',
      'stats': {
        'packages': packagesCount,
        'users': users.length,
        'activeUsers': activeUsersCount,
        'adminUsers': adminUsersCount,
      },
      'recentLogs': recentLogs.map((log) {
        return {
          'action': log.action,
          'userId': log.userId,
          'resourceType': log.resourceType,
          'resourceId': log.resourceId,
          'createdAt': log.createdAt.toUtc().toIso8601String(),
        };
      }).toList(),
    });

    return Response.ok(
      html,
      headers: {'Content-Type': 'text/html'},
    );
  }

  /// GET /admin/users
  ///
  /// User management page.
  Future<Response> usersPage(Request request) async {
    final queryParams = request.url.queryParameters;
    final status = queryParams['status'];
    final role = queryParams['role'];
    final search = queryParams['search'];

    final usersResult = await userRepository.listAll(
      status: status,
      role: role,
      searchQuery: search,
    );

    final users = switch (usersResult) {
      Ok(value: final u) => u,
      Error() => <User>[],
    };

    // Render template
    final html = _renderTemplate('users.html', {
      'title': 'User Management',
      'users': users.map((user) {
        return {
          'id': user.id,
          'email': user.email,
          'displayName': user.displayName ?? '',
          'role': user.role,
          'status': user.status,
          'isActive': user.status == 'active',
          'lastLoginAt': user.lastLoginAt?.toUtc().toIso8601String() ?? 'Never',
          'createdAt': user.createdAt.toUtc().toIso8601String(),
        };
      }).toList(),
      'filters': {
        'status': status ?? '',
        'role': role ?? '',
        'search': search ?? '',
      },
    });

    return Response.ok(
      html,
      headers: {'Content-Type': 'text/html'},
    );
  }

  /// GET /admin/packages
  ///
  /// Package management page.
  Future<Response> packagesPage(Request request) async {
    final queryParams = request.url.queryParameters;
    final search = queryParams['search'];

    final packagesResult = await packageRepository.listAll(
      searchQuery: search,
    );

    final packages = switch (packagesResult) {
      Ok(value: final p) => p,
      Error() => <Package>[],
    };

    // Get version counts and uploader counts for each package
    final packageData = <Map<String, dynamic>>[];
    for (final package in packages) {
      final versionsResult = await versionRepository.listForPackage(package.id);
      final versions = switch (versionsResult) {
        Ok(value: final v) => v,
        Error() => <Version>[],
      };

      final uploadersResult =
          await packageUploaderRepository.listUploaders(package.id);
      final uploaders = switch (uploadersResult) {
        Ok(value: final u) => u,
        Error() => <User>[],
      };

      packageData.add({
        'id': package.id,
        'name': package.name,
        'description': package.description ?? '',
        'isPrivate': package.isPrivate,
        'versionCount': versions.length,
        'uploaderCount': uploaders.length,
        'createdAt': package.createdAt.toUtc().toIso8601String(),
      });
    }

    // Render template
    final html = _renderTemplate('packages.html', {
      'title': 'Package Management',
      'packages': packageData,
      'filters': {
        'search': search ?? '',
      },
    });

    return Response.ok(
      html,
      headers: {'Content-Type': 'text/html'},
    );
  }

  /// Loads and renders a Mustache template with the admin layout.
  String _renderTemplate(String contentName, Map<String, dynamic> data) {
    final layoutPath = '$templateDir/admin/layout.html';
    final contentPath = '$templateDir/admin/$contentName';

    final layoutSource = File(layoutPath).readAsStringSync();
    final contentSource = File(contentPath).readAsStringSync();

    // First render the content template with data
    final contentTemplate = Template(contentSource);
    final renderedContent = contentTemplate.renderString(data);

    // Then render the layout with the rendered content
    final layoutTemplate = Template(layoutSource);
    return layoutTemplate.renderString({
      ...data,
      'content': renderedContent,
      'version': '0.1.0',
    });
  }
}
