import 'dart:convert';

import 'package:darktar/data/database.dart';
import 'package:darktar/data/repositories/audit_log_repository.dart';
import 'package:darktar/data/repositories/package_repository.dart';
import 'package:darktar/data/repositories/package_uploader_repository.dart';
import 'package:darktar/data/repositories/user_repository.dart';
import 'package:darktar/data/repositories/version_repository.dart';
import 'package:darktar/data/result.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// Handlers for admin API endpoints.
class AdminHandlers {
  AdminHandlers({required this.db})
      : userRepository = UserRepository(db),
        packageRepository = PackageRepository(db),
        versionRepository = VersionRepository(db),
        packageUploaderRepository = PackageUploaderRepository(db),
        auditLogRepository = AuditLogRepository(db);

  final DarktarDatabase db;
  final UserRepository userRepository;
  final PackageRepository packageRepository;
  final VersionRepository versionRepository;
  final PackageUploaderRepository packageUploaderRepository;
  final AuditLogRepository auditLogRepository;

  /// Registers routes on the provided router.
  void registerRoutes(Router router) {
    // User management
    router.get('/users', listUsers);
    router.get('/users/<id>', getUser);
    router.put('/users/<id>', updateUser);
    router.delete('/users/<id>', deleteUser);

    // Package management
    router.get('/packages', listPackages);
    router.put('/packages/<name>/uploaders', updatePackageUploaders);

    // Statistics
    router.get('/stats', getStats);

    // Audit logs
    router.get('/audit-logs', listAuditLogs);
  }

  /// Helper function to log admin actions.
  Future<void> _logAction({
    required Request request,
    required String action,
    required String resourceType,
    int? resourceId,
  }) async {
    final user = request.context['user'] as User?;
    await auditLogRepository.create(
      userId: user?.id,
      action: action,
      resourceType: resourceType,
      resourceId: resourceId,
      ipAddress: request.headers['x-forwarded-for'] ??
          request.headers['x-real-ip'] ??
          'unknown',
      userAgent: request.headers['user-agent'],
    );
  }

  /// GET /api/admin/users
  ///
  /// Lists all users with optional filters.
  Future<Response> listUsers(Request request) async {
    final queryParams = request.url.queryParameters;
    final limit = int.tryParse(queryParams['limit'] ?? '50');
    final offset = int.tryParse(queryParams['offset'] ?? '0');
    final status = queryParams['status'];
    final role = queryParams['role'];
    final search = queryParams['search'];

    final result = await userRepository.listAll(
      limit: limit,
      offset: offset,
      status: status,
      role: role,
      searchQuery: search,
    );

    return switch (result) {
      Ok(value: final users) => Response.ok(
          jsonEncode({
            'users': users.map((u) => _userToJson(u)).toList(),
          }),
          headers: {'Content-Type': 'application/json'},
        ),
      Error(error: final e) => Response.internalServerError(
          body: '{"error":"Failed to list users: $e"}',
          headers: {'Content-Type': 'application/json'},
        ),
    };
  }

  /// GET /api/admin/users/:id
  ///
  /// Gets a specific user by ID.
  Future<Response> getUser(Request request, String id) async {
    final userId = int.tryParse(id);
    if (userId == null) {
      return Response.badRequest(
        body: '{"error":"Invalid user ID"}',
        headers: {'Content-Type': 'application/json'},
      );
    }

    final result = await userRepository.getById(userId);

    return switch (result) {
      Ok(value: final user) => Response.ok(
          jsonEncode(_userToJson(user)),
          headers: {'Content-Type': 'application/json'},
        ),
      Error() => Response.notFound(
          '{"error":"User not found"}',
          headers: {'Content-Type': 'application/json'},
        ),
    };
  }

  /// PUT /api/admin/users/:id
  ///
  /// Updates a user.
  Future<Response> updateUser(Request request, String id) async {
    final userId = int.tryParse(id);
    if (userId == null) {
      return Response.badRequest(
        body: '{"error":"Invalid user ID"}',
        headers: {'Content-Type': 'application/json'},
      );
    }

    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final result = await userRepository.update(
        userId: userId,
        email: data['email'] as String?,
        displayName: data['displayName'] as String?,
        role: data['role'] as String?,
        status: data['status'] as String?,
        isAdmin: data['isAdmin'] as bool?,
      );

      return switch (result) {
        Ok(value: final user) => () async {
            // Log the action
            final roleChanged = data['role'] != null;
            await _logAction(
              request: request,
              action:
                  roleChanged ? 'admin.user.role_change' : 'admin.user.update',
              resourceType: 'user',
              resourceId: userId,
            );

            return Response.ok(
              jsonEncode(_userToJson(user)),
              headers: {'Content-Type': 'application/json'},
            );
          }(),
        Error(error: final e) => Response.badRequest(
            body: '{"error":"Failed to update user: $e"}',
            headers: {'Content-Type': 'application/json'},
          ),
      };
    } on Exception catch (e) {
      return Response.badRequest(
        body: '{"error":"Invalid request: $e"}',
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// DELETE /api/admin/users/:id
  ///
  /// Deletes (soft delete) a user.
  Future<Response> deleteUser(Request request, String id) async {
    final userId = int.tryParse(id);
    if (userId == null) {
      return Response.badRequest(
        body: '{"error":"Invalid user ID"}',
        headers: {'Content-Type': 'application/json'},
      );
    }

    final result = await userRepository.delete(userId);

    return switch (result) {
      Ok() => () async {
          // Log the action
          await _logAction(
            request: request,
            action: 'admin.user.delete',
            resourceType: 'user',
            resourceId: userId,
          );

          return Response.ok(
            '{"message":"User deleted successfully"}',
            headers: {'Content-Type': 'application/json'},
          );
        }(),
      Error(error: final e) => Response.internalServerError(
          body: '{"error":"Failed to delete user: $e"}',
          headers: {'Content-Type': 'application/json'},
        ),
    };
  }

  /// GET /api/admin/packages
  ///
  /// Lists all packages with statistics.
  Future<Response> listPackages(Request request) async {
    final queryParams = request.url.queryParameters;
    final limit = int.tryParse(queryParams['limit'] ?? '50');
    final offset = int.tryParse(queryParams['offset'] ?? '0');
    final search = queryParams['search'];

    final packagesResult = await packageRepository.listAll(
      limit: limit,
      offset: offset,
      searchQuery: search,
    );

    return switch (packagesResult) {
      Ok(value: final packages) => () async {
          final packageData = <Map<String, dynamic>>[];

          for (final package in packages) {
            final versionsResult =
                await versionRepository.listForPackage(package.id);
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
              'description': package.description,
              'isDiscontinued': package.isDiscontinued,
              'isPrivate': package.isPrivate,
              'versionCount': versions.length,
              'uploaderCount': uploaders.length,
              'createdAt': package.createdAt.toUtc().toIso8601String(),
            });
          }

          return Response.ok(
            jsonEncode({'packages': packageData}),
            headers: {'Content-Type': 'application/json'},
          );
        }(),
      Error(error: final e) => Response.internalServerError(
          body: '{"error":"Failed to list packages: $e"}',
          headers: {'Content-Type': 'application/json'},
        ),
    };
  }

  /// PUT /api/admin/packages/:name/uploaders
  ///
  /// Updates package uploaders.
  Future<Response> updatePackageUploaders(
    Request request,
    String name,
  ) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final userIds = (data['userIds'] as List?)?.cast<int>() ?? [];

      final packageResult = await packageRepository.getByName(name);
      final package = switch (packageResult) {
        Ok(value: final p) => p,
        Error() => null,
      };

      if (package == null) {
        return Response.notFound(
          '{"error":"Package not found"}',
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get current uploaders
      final currentUploadersResult =
          await packageUploaderRepository.listUploaders(package.id);
      final currentUploaders = switch (currentUploadersResult) {
        Ok(value: final u) => u.map((u) => u.id).toSet(),
        Error() => <int>{},
      };

      final newUploaderIds = userIds.toSet();

      // Remove uploaders not in the new list
      for (final userId in currentUploaders) {
        if (!newUploaderIds.contains(userId)) {
          await packageUploaderRepository.removeUploader(
            packageId: package.id,
            userId: userId,
          );
        }
      }

      // Add new uploaders
      for (final userId in newUploaderIds) {
        if (!currentUploaders.contains(userId)) {
          await packageUploaderRepository.addUploader(
            packageId: package.id,
            userId: userId,
          );
        }
      }

      final updatedUploadersResult =
          await packageUploaderRepository.listUploaders(package.id);
      final updatedUploaders = switch (updatedUploadersResult) {
        Ok(value: final u) => u,
        Error() => <User>[],
      };

      // Log the action
      await _logAction(
        request: request,
        action: 'admin.package.uploader_change',
        resourceType: 'package',
        resourceId: package.id,
      );

      return Response.ok(
        jsonEncode({
          'uploaders': updatedUploaders.map((u) => _userToJson(u)).toList(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } on Exception catch (e) {
      return Response.badRequest(
        body: '{"error":"Invalid request: $e"}',
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /api/admin/stats
  ///
  /// Returns system statistics.
  Future<Response> getStats(Request request) async {
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

    return Response.ok(
      jsonEncode({
        'packages': packagesCount,
        'users': users.length,
        'activeUsers': activeUsersCount,
        'adminUsers': adminUsersCount,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// GET /api/admin/audit-logs
  ///
  /// Lists audit logs with optional filters.
  Future<Response> listAuditLogs(Request request) async {
    final queryParams = request.url.queryParameters;
    final limit = int.tryParse(queryParams['limit'] ?? '100');
    final offset = int.tryParse(queryParams['offset'] ?? '0');
    final userId = int.tryParse(queryParams['userId'] ?? '');
    final action = queryParams['action'];
    final resourceType = queryParams['resourceType'];
    final resourceId = int.tryParse(queryParams['resourceId'] ?? '');

    final result = await auditLogRepository.list(
      limit: limit,
      offset: offset,
      userId: userId,
      action: action,
      resourceType: resourceType,
      resourceId: resourceId,
    );

    return switch (result) {
      Ok(value: final logs) => Response.ok(
          jsonEncode({
            'logs': logs
                .map((log) => {
                      'id': log.id,
                      'userId': log.userId,
                      'action': log.action,
                      'resourceType': log.resourceType,
                      'resourceId': log.resourceId,
                      'ipAddress': log.ipAddress,
                      'userAgent': log.userAgent,
                      'createdAt': log.createdAt.toUtc().toIso8601String(),
                    })
                .toList(),
          }),
          headers: {'Content-Type': 'application/json'},
        ),
      Error(error: final e) => Response.internalServerError(
          body: '{"error":"Failed to list audit logs: $e"}',
          headers: {'Content-Type': 'application/json'},
        ),
    };
  }

  /// Converts a User to JSON.
  Map<String, dynamic> _userToJson(User user) {
    return {
      'id': user.id,
      'email': user.email,
      'displayName': user.displayName,
      'isAdmin': user.isAdmin,
      'role': user.role,
      'status': user.status,
      'lastLoginAt': user.lastLoginAt?.toUtc().toIso8601String(),
      'createdAt': user.createdAt.toUtc().toIso8601String(),
      'updatedAt': user.updatedAt?.toUtc().toIso8601String(),
    };
  }
}
