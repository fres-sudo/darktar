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
        Ok(value: final user) => innerHandler(
            request.change(context: {'user': user}),
          ),
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

/// Extension to extract user from request context.
extension AuthRequestX on Request {
  /// Gets the authenticated user from the request context.
  User? get user => context['user'] as User?;

  /// Returns true if the request is authenticated.
  bool get isAuthenticated => user != null;
}
