import 'package:drift/drift.dart';

import '../database.dart';
import '../result.dart';

/// Exception for package-related errors.
class PackageException implements Exception {
  const PackageException(this.message);
  final String message;

  @override
  String toString() => 'PackageException: $message';
}

/// Repository for package operations.
class PackageRepository {
  const PackageRepository(this._db);

  final DarktarDatabase _db;

  /// Gets a package by name.
  Future<Result<Package>> getByName(String name) async {
    try {
      final query = _db.select(_db.packages)
        ..where((p) => p.name.equals(name));
      final package = await query.getSingleOrNull();

      if (package == null) {
        return Result.error(
          PackageException('Package not found: $name'),
        );
      }

      return Result.ok(package);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Lists all packages with optional pagination.
  Future<Result<List<Package>>> listAll({
    int? limit,
    int? offset,
    String? searchQuery,
  }) async {
    try {
      var query = _db.select(_db.packages);

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query
          ..where(
            (p) =>
                p.name.like('%$searchQuery%') |
                p.description.like('%$searchQuery%'),
          );
      }

      query = query..orderBy([(p) => OrderingTerm.desc(p.createdAt)]);

      if (limit != null) {
        query = query..limit(limit, offset: offset);
      }

      final packages = await query.get();
      return Result.ok(packages);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Creates a new package.
  Future<Result<Package>> create({
    required String name,
    String? description,
  }) async {
    try {
      // Check if package already exists
      final existing = await getByName(name);
      if (existing.isSuccess) {
        return Result.error(
          PackageException('Package already exists: $name'),
        );
      }

      final id = await _db.into(_db.packages).insert(
        PackagesCompanion.insert(
          name: name,
          description: Value(description),
        ),
      );

      final query = _db.select(_db.packages)..where((p) => p.id.equals(id));
      final package = await query.getSingle();

      return Result.ok(package);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Updates a package.
  Future<Result<Package>> update({
    required int id,
    String? description,
    bool? isDiscontinued,
    String? replacedBy,
  }) async {
    try {
      await (_db.update(_db.packages)..where((p) => p.id.equals(id))).write(
        PackagesCompanion(
          description: description != null ? Value(description) : Value.absent(),
          isDiscontinued:
              isDiscontinued != null ? Value(isDiscontinued) : Value.absent(),
          replacedBy: replacedBy != null ? Value(replacedBy) : Value.absent(),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final query = _db.select(_db.packages)..where((p) => p.id.equals(id));
      final package = await query.getSingleOrNull();

      if (package == null) {
        return Result.error(PackageException('Package not found: $id'));
      }

      return Result.ok(package);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Gets the count of packages.
  Future<Result<int>> count() async {
    try {
      final query = _db.selectOnly(_db.packages)
        ..addColumns([_db.packages.id.count()]);
      final result = await query.getSingle();
      final count = result.read(_db.packages.id.count()) ?? 0;
      return Result.ok(count);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }
}
