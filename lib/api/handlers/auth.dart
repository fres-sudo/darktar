import 'dart:convert';
import 'dart:math';

import 'package:darktar/data/database.dart';
import 'package:darktar/data/repositories/user_repository.dart';
import 'package:darktar/data/result.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// Handlers for authentication API endpoints.
class AuthHandlers {
  AuthHandlers({required this.db}) : userRepository = UserRepository(db);

  final DarktarDatabase db;
  final UserRepository userRepository;

  /// Registers routes on the provided router.
  void registerRoutes(Router router) {
    router.post('/api/auth/register', register);
    router.post('/api/auth/token', generateToken);
    router.delete('/api/auth/token', revokeToken);
    router.get('/api/auth/me', getCurrentUser);
  }

  /// Parses the request body as either JSON or form-encoded data.
  Future<Map<String, dynamic>> _parseRequestBody(Request request) async {
    final contentType = request.headers['content-type'] ?? '';
    final body = await request.readAsString();

    if (contentType.contains('application/json')) {
      return jsonDecode(body) as Map<String, dynamic>;
    } else if (contentType.contains('application/x-www-form-urlencoded')) {
      // Parse URL-encoded form data
      final formData = <String, dynamic>{};
      final pairs = body.split('&');
      for (final pair in pairs) {
        final parts = pair.split('=');
        if (parts.length == 2) {
          final key = Uri.decodeComponent(parts[0]);
          final value = Uri.decodeComponent(parts[1]);
          formData[key] = value;
        }
      }
      return formData;
    } else {
      // Try JSON first, fallback to form-encoded
      try {
        return jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        // Parse as form-encoded
        final formData = <String, dynamic>{};
        final pairs = body.split('&');
        for (final pair in pairs) {
          final parts = pair.split('=');
          if (parts.length == 2) {
            final key = Uri.decodeComponent(parts[0]);
            final value = Uri.decodeComponent(parts[1]);
            formData[key] = value;
          }
        }
        return formData;
      }
    }
  }

  /// POST /api/auth/register
  ///
  /// Registers a new user and returns their token.
  Future<Response> register(Request request) async {
    try {
      final data = await _parseRequestBody(request);

      final email = data['email'] as String?;
      final name = data['name'] as String?;

      if (email == null || email.isEmpty) {
        return Response.badRequest(
          body: '{"error":"Email is required"}',
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Check if user already exists
      final existingResult = await userRepository.getByEmail(email);
      if (existingResult.isSuccess) {
        return Response(
          409, // Conflict
          body: '{"error":"User already exists with this email"}',
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Create the user (token is generated internally)
      final createResult = await userRepository.create(
        email: email,
        displayName: name ?? email.split('@').first,
      );

      return switch (createResult) {
        Ok(value: final user) => Response.ok(
            jsonEncode({
              'user': {
                'id': user.id,
                'email': user.email,
                'name': user.displayName,
              },
              'token': user.token,
            }),
            headers: {'Content-Type': 'application/json'},
          ),
        Error(error: final e) => Response.internalServerError(
            body: '{"error":"Failed to create user: $e"}',
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

  /// POST /api/auth/token
  ///
  /// Generates a new token for an existing user.
  Future<Response> generateToken(Request request) async {
    try {
      final data = await _parseRequestBody(request);

      final email = data['email'] as String?;

      if (email == null || email.isEmpty) {
        return Response.badRequest(
          body: '{"error":"Email is required"}',
          headers: {'Content-Type': 'application/json'},
        );
      }

      final userResult = await userRepository.getByEmail(email);

      return switch (userResult) {
        Ok(value: final user) => () async {
            // Generate a new token
            final newToken = _generateToken();

            // Update the user's token
            final updateResult =
                await userRepository.updateToken(user.id, newToken);

            return switch (updateResult) {
              Ok(value: final updated) => Response.ok(
                  jsonEncode({
                    'user': {
                      'id': updated.id,
                      'email': updated.email,
                      'name': updated.displayName,
                    },
                    'token': newToken,
                  }),
                  headers: {'Content-Type': 'application/json'},
                ),
              Error(error: final e) => Response.internalServerError(
                  body: '{"error":"Failed to generate token: $e"}',
                  headers: {'Content-Type': 'application/json'},
                ),
            };
          }(),
        Error() => Response.notFound(
            '{"error":"User not found. Please register first."}',
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

  /// DELETE /api/auth/token
  ///
  /// Revokes the current user's token.
  Future<Response> revokeToken(Request request) async {
    final user = request.context['user'] as User?;

    if (user == null) {
      return Response.unauthorized(
        '{"error":"Authentication required"}',
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Generate a new token to invalidate the old one
    final newToken = _generateToken();
    final updateResult = await userRepository.updateToken(user.id, newToken);

    return switch (updateResult) {
      Ok() => Response.ok(
          '{"message":"Token revoked successfully"}',
          headers: {'Content-Type': 'application/json'},
        ),
      Error(error: final e) => Response.internalServerError(
          body: '{"error":"Failed to revoke token: $e"}',
          headers: {'Content-Type': 'application/json'},
        ),
    };
  }

  /// GET /api/auth/me
  ///
  /// Returns the current authenticated user's info.
  Future<Response> getCurrentUser(Request request) async {
    final user = request.context['user'] as User?;

    if (user == null) {
      return Response.unauthorized(
        '{"error":"Authentication required"}',
        headers: {'Content-Type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode({
        'id': user.id,
        'email': user.email,
        'name': user.displayName,
        'isAdmin': user.isAdmin,
        'createdAt': user.createdAt.toUtc().toIso8601String(),
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// Generates a secure random token.
  String _generateToken() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return 'dkt_${List.generate(32, (_) => chars[random.nextInt(chars.length)]).join()}';
  }
}
