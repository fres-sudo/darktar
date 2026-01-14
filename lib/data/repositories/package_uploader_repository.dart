import 'package:drift/drift.dart';

import '../database.dart';
import '../result.dart';

/// Exception for package uploader-related errors.
class PackageUploaderException implements Exception {
  const PackageUploaderException(this.message);
  final String message;

  @override
  String toString() => 'PackageUploaderException: $message';
}

/// Repository for package uploader operations.
class PackageUploaderRepository {
  const PackageUploaderRepository(this._db);

  final DarktarDatabase _db;

  /// Adds an uploader to a package.
  Future<Result<void>> addUploader({
    required int packageId,
    required int userId,
  }) async {
    try {
      await _db.into(_db.packageUploaders).insert(
            PackageUploadersCompanion.insert(
              packageId: packageId,
              userId: userId,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      return const Result.ok(null);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Removes an uploader from a package.
  Future<Result<void>> removeUploader({
    required int packageId,
    required int userId,
  }) async {
    try {
      final deleted = await (_db.delete(_db.packageUploaders)
            ..where(
              (pu) => pu.packageId.equals(packageId) & pu.userId.equals(userId),
            ))
          .go();

      if (deleted == 0) {
        return Result.error(
          const PackageUploaderException('Uploader not found'),
        );
      }

      return const Result.ok(null);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Lists all uploaders for a package.
  Future<Result<List<User>>> listUploaders(int packageId) async {
    try {
      final query = _db.select(_db.users).join([
        innerJoin(
          _db.packageUploaders,
          _db.packageUploaders.userId.equalsExp(_db.users.id),
        ),
      ])
        ..where(_db.packageUploaders.packageId.equals(packageId));

      final results = await query.get();
      final users = results.map((row) => row.readTable(_db.users)).toList();

      return Result.ok(users);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Checks if a user can publish to a package.
  Future<Result<bool>> canPublish({
    required int packageId,
    required int userId,
  }) async {
    try {
      final query = _db.selectOnly(_db.packageUploaders)
        ..addColumns([_db.packageUploaders.userId.count()])
        ..where(
          _db.packageUploaders.packageId.equals(packageId) &
              _db.packageUploaders.userId.equals(userId),
        );

      final result = await query.getSingle();
      final count = result.read(_db.packageUploaders.userId.count()) ?? 0;

      return Result.ok(count > 0);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Removes all uploaders from a package (used when deleting packages).
  Future<Result<void>> removeAllUploaders(int packageId) async {
    try {
      await (_db.delete(_db.packageUploaders)
            ..where((pu) => pu.packageId.equals(packageId)))
          .go();
      return const Result.ok(null);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }
}
