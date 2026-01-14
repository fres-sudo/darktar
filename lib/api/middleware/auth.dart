import 'dart:async';

import 'package:darktar/data/database.dart';
import 'package:darktar/data/repositories/user_repository.dart';
import 'package:darktar/data/result.dart';
import 'package:shelf/shelf.dart';

/// Authentication middleware for Bearer token validation.
///
/// Validates the Authorization header and adds user information to the request context.
Middleware authMiddleware(DarktarDatabase db) {
  final userRepository = UserRepository(db);

  return (Handler innerHandler) {
    return (Request request) async {
      // Skip auth for certain paths
      if (_isPublicPath(request.url.path)) {
        return innerHandler(request);
      }

      final authHeader = request.headers['authorization'];

      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response.unauthorized(
          '{"error":"Missing or invalid Authorization header"}',
          headers: {'Content-Type': 'application/json'},
        );
      }

      final token = authHeader.substring(7); // Remove 'Bearer ' prefix

      final userResult = await userRepository.getByToken(token);

      return switch (userResult) {
        Ok(value: final user) => () async {
            // Check if user is active
            if (user.status != 'active') {
              return Response.unauthorized(
                '{"error":"User account is ${user.status}"}',
                headers: {'Content-Type': 'application/json'},
              );
            }

            // Record login time (fire and forget)
            unawaited(userRepository.recordLogin(user.id));

            return await innerHandler(
              request.change(context: {'user': user}),
            );
          }(),
        Error() => Response.unauthorized(
            '{"error":"Invalid token"}',
            headers: {'Content-Type': 'application/json'},
          ),
      };
    };
  };
}

/// Checks if a path is public (doesn't require auth).
bool _isPublicPath(String path) {
  const publicPaths = [
    'health',
    'api/packages', // GET is public, POST requires auth (handled separately)
    'packages', // Archive downloads are public in most registries
  ];

  for (final publicPath in publicPaths) {
    if (path == publicPath || path.startsWith('$publicPath/')) {
      return true;
    }
  }

  return false;
}

/// Middleware that requires admin role.
Middleware requireAdmin() {
  return (Handler innerHandler) {
    return (Request request) {
      final user = request.user;

      if (user == null) {
        return Response.unauthorized(
          '{"error":"Authentication required"}',
          headers: {'Content-Type': 'application/json'},
        );
      }

      final isAdmin =
          user.isAdmin || user.role == 'admin' || user.role == 'super_admin';

      if (!isAdmin) {
        return Response.forbidden(
          '{"error":"Admin access required"}',
          headers: {'Content-Type': 'application/json'},
        );
      }

      return innerHandler(request);
    };
  };
}

/// Extension to extract user from request context.
extension AuthRequestX on Request {
  /// Gets the authenticated user from the request context.
  User? get user => context['user'] as User?;

  /// Returns true if the request is authenticated.
  bool get isAuthenticated => user != null;

  /// Returns true if the user is an admin.
  bool get isAdmin {
    final u = user;
    if (u == null) return false;
    return u.isAdmin || u.role == 'admin' || u.role == 'super_admin';
  }

  /// Returns true if the user is a super admin.
  bool get isSuperAdmin {
    final u = user;
    if (u == null) return false;
    return u.role == 'super_admin';
  }
}
