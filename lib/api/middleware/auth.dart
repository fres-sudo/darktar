import 'dart:async';
import 'dart:convert';

import 'package:darktar/data/database.dart';
import 'package:darktar/data/repositories/user_repository.dart';
import 'package:darktar/data/result.dart';
import 'package:shelf/shelf.dart';

/// Authentication middleware for Bearer token and Basic Auth validation.
///
/// Validates the Authorization header and adds user information to the request context.
/// Supports both Bearer tokens (for API) and Basic Auth (for Pub protocol).
Middleware authMiddleware(DarktarDatabase db) {
  final userRepository = UserRepository(db);

  return (Handler innerHandler) {
    return (Request request) async {
      // Skip auth for certain paths
      if (_isPublicPath(request.url.path)) {
        return innerHandler(request);
      }

      final authHeader = request.headers['authorization'];

      if (authHeader == null) {
        return Response.unauthorized(
          '{"error":"Missing Authorization header"}',
          headers: {'Content-Type': 'application/json'},
        );
      }

      String? token;

      // Try Bearer token first
      if (authHeader.startsWith('Bearer ')) {
        token = authHeader.substring(7); // Remove 'Bearer ' prefix
      }
      // Try Basic Auth (used by dart pub publish)
      else if (authHeader.startsWith('Basic ')) {
        try {
          final encoded = authHeader.substring(6); // Remove 'Basic ' prefix
          final decoded = utf8.decode(base64Decode(encoded));
          // Basic Auth format: "username:password" or ":token" or "token:"
          final parts = decoded.split(':');
          // For Pub protocol, token is typically the password (second part)
          // or the entire string if there's no colon
          if (parts.length == 2) {
            // Use the non-empty part (either username or password)
            token = parts[0].isEmpty ? parts[1] : parts[0];
          } else {
            // No colon, use the entire decoded string as token
            token = decoded;
          }
        } catch (e) {
          return Response.unauthorized(
            '{"error":"Invalid Basic Auth encoding"}',
            headers: {'Content-Type': 'application/json'},
          );
        }
      } else {
        return Response.unauthorized(
          '{"error":"Unsupported Authorization method. Use Bearer or Basic"}',
          headers: {'Content-Type': 'application/json'},
        );
      }

      // At this point, token should be set, but verify it's not empty
      if (token.isEmpty) {
        return Response.unauthorized(
          '{"error":"Token not found in Authorization header"}',
          headers: {'Content-Type': 'application/json'},
        );
      }

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
  // Root path is public
  if (path == '' || path == '/') {
    return true;
  }

  // Remove leading slash for matching
  final normalizedPath = path.startsWith('/') ? path.substring(1) : path;

  const publicPaths = [
    'health',
    'api/packages', // GET is public, POST requires auth (handled separately)
    'packages', // Archive downloads and web UI package pages
    'auth', // Auth page for token generation
    'static', // Static assets
    'docs', // Documentation
    'api/auth/register', // User registration
    'api/auth/token', // Token generation
  ];

  for (final publicPath in publicPaths) {
    if (normalizedPath == publicPath ||
        normalizedPath.startsWith('$publicPath/')) {
      return true;
    }
  }

  // Allow web UI routes (not API routes) to be public
  // API routes start with /api/ and should require auth (except those listed above)
  if (!normalizedPath.startsWith('api/')) {
    return true;
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
