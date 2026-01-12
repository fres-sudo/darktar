import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database.dart';
import '../result.dart';

/// Exception for user-related errors.
class UserException implements Exception {
  const UserException(this.message);
  final String message;

  @override
  String toString() => 'UserException: $message';
}

/// Repository for user operations.
class UserRepository {
  const UserRepository(this._db);

  final DarktarDatabase _db;

  static const _uuid = Uuid();

  /// Gets a user by their authentication token.
  Future<Result<User>> getByToken(String token) async {
    try {
      final query = _db.select(_db.users)
        ..where((u) => u.token.equals(token));

      final user = await query.getSingleOrNull();

      if (user == null) {
        return const Result.error(UserException('Invalid token'));
      }

      return Result.ok(user);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Gets a user by email.
  Future<Result<User>> getByEmail(String email) async {
    try {
      final query = _db.select(_db.users)
        ..where((u) => u.email.equals(email));

      final user = await query.getSingleOrNull();

      if (user == null) {
        return Result.error(UserException('User not found: $email'));
      }

      return Result.ok(user);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Creates a new user with a generated token.
  Future<Result<User>> create({
    required String email,
    String? displayName,
    bool isAdmin = false,
  }) async {
    try {
      // Check if user already exists
      final existingResult = await getByEmail(email);
      if (existingResult.isSuccess) {
        return Result.error(UserException('User already exists: $email'));
      }

      final token = _generateToken();

      final id = await _db.into(_db.users).insert(
        UsersCompanion.insert(
          email: email,
          token: token,
          displayName: Value(displayName),
          isAdmin: Value(isAdmin),
        ),
      );

      final query = _db.select(_db.users)..where((u) => u.id.equals(id));
      final user = await query.getSingle();

      return Result.ok(user);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Regenerates a token for a user.
  Future<Result<User>> regenerateToken(int userId) async {
    try {
      final newToken = _generateToken();

      await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
        UsersCompanion(
          token: Value(newToken),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final query = _db.select(_db.users)..where((u) => u.id.equals(userId));
      final user = await query.getSingleOrNull();

      if (user == null) {
        return const Result.error(UserException('User not found'));
      }

      return Result.ok(user);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Lists all users.
  Future<Result<List<User>>> listAll({int? limit, int? offset}) async {
    try {
      var query = _db.select(_db.users);
      query = query..orderBy([(u) => OrderingTerm.asc(u.email)]);

      if (limit != null) {
        query = query..limit(limit, offset: offset);
      }

      final users = await query.get();
      return Result.ok(users);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Generates a secure token.
  static String _generateToken() {
    return 'dkt_${_uuid.v4().replaceAll('-', '')}';
  }
}
