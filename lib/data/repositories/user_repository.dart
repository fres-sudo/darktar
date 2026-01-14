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
      final query = _db.select(_db.users)..where((u) => u.token.equals(token));

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
      final query = _db.select(_db.users)..where((u) => u.email.equals(email));

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
      final role = isAdmin ? 'admin' : 'user';

      final id = await _db.into(_db.users).insert(
            UsersCompanion.insert(
              email: email,
              token: token,
              displayName: Value(displayName),
              isAdmin: Value(isAdmin),
              role: Value(role),
            ),
          );

      final query = _db.select(_db.users)..where((u) => u.id.equals(id));
      final user = await query.getSingle();

      return Result.ok(user);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Updates a user's token.
  Future<Result<User>> updateToken(int userId, String newToken) async {
    try {
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

  /// Gets a user by ID.
  Future<Result<User>> getById(int userId) async {
    try {
      final query = _db.select(_db.users)..where((u) => u.id.equals(userId));

      final user = await query.getSingleOrNull();

      if (user == null) {
        return Result.error(UserException('User not found: $userId'));
      }

      return Result.ok(user);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Lists all users with optional filters.
  Future<Result<List<User>>> listAll({
    int? limit,
    int? offset,
    String? status,
    String? role,
    String? searchQuery,
  }) async {
    try {
      var query = _db.select(_db.users);

      if (status != null) {
        query = query..where((u) => u.status.equals(status));
      }

      if (role != null) {
        query = query..where((u) => u.role.equals(role));
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query
          ..where(
            (u) =>
                u.email.like('%$searchQuery%') |
                u.displayName.like('%$searchQuery%'),
          );
      }

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

  /// Updates a user.
  Future<Result<User>> update({
    required int userId,
    String? email,
    String? displayName,
    String? role,
    String? status,
    bool? isAdmin,
  }) async {
    try {
      final companion = UsersCompanion(
        email: email != null ? Value(email) : Value.absent(),
        displayName: displayName != null ? Value(displayName) : Value.absent(),
        role: role != null ? Value(role) : Value.absent(),
        status: status != null ? Value(status) : Value.absent(),
        isAdmin: isAdmin != null ? Value(isAdmin) : Value.absent(),
        updatedAt: Value(DateTime.now()),
      );

      await (_db.update(_db.users)..where((u) => u.id.equals(userId)))
          .write(companion);

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

  /// Updates a user's role.
  Future<Result<User>> updateRole(int userId, String role) async {
    return update(userId: userId, role: role);
  }

  /// Updates a user's status.
  Future<Result<User>> updateStatus(int userId, String status) async {
    return update(userId: userId, status: status);
  }

  /// Records a user's login time.
  Future<Result<User>> recordLogin(int userId) async {
    try {
      await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
        UsersCompanion(
          lastLoginAt: Value(DateTime.now()),
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

  /// Deletes (soft delete) a user by setting status to 'deleted'.
  Future<Result<void>> delete(int userId) async {
    try {
      final result = await updateStatus(userId, 'deleted');
      return switch (result) {
        Ok() => const Result.ok(null),
        Error(error: final e) => Result.error(e),
      };
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Generates a secure token.
  static String _generateToken() {
    return 'dkt_${_uuid.v4().replaceAll('-', '')}';
  }
}
