import 'package:drift/drift.dart';
import 'package:pub_semver/pub_semver.dart' as semver;

import '../database.dart';
import '../result.dart';

/// Exception for version-related errors.
class VersionException implements Exception {
  const VersionException(this.message);
  final String message;

  @override
  String toString() => 'VersionException: $message';
}

/// Repository for version operations.
class VersionRepository {
  const VersionRepository(this._db);

  final DarktarDatabase _db;

  /// Gets all versions for a package.
  Future<Result<List<Version>>> listForPackage(int packageId) async {
    try {
      final query = _db.select(_db.versions)
        ..where((v) => v.packageId.equals(packageId))
        ..orderBy([
          (v) => OrderingTerm.desc(v.createdAt),
        ]);

      final versions = await query.get();
      return Result.ok(versions);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Gets a specific version of a package.
  Future<Result<Version>> get({
    required int packageId,
    required String version,
  }) async {
    try {
      final query = _db.select(_db.versions)
        ..where(
          (v) => v.packageId.equals(packageId) & v.version.equals(version),
        );

      final versionRow = await query.getSingleOrNull();

      if (versionRow == null) {
        return Result.error(VersionException('Version not found: $version'));
      }

      return Result.ok(versionRow);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Gets the latest version of a package.
  Future<Result<Version>> getLatest(int packageId) async {
    try {
      final versionsResult = await listForPackage(packageId);

      switch (versionsResult) {
        case Ok(value: final versions):
          if (versions.isEmpty) {
            return const Result.error(
              VersionException('No versions found for package'),
            );
          }

          // Sort by semantic version (descending)
          versions.sort((a, b) {
            final vA = semver.Version.parse(a.version);
            final vB = semver.Version.parse(b.version);
            return vB.compareTo(vA);
          });

          return Result.ok(versions.first);

        case Error(error: final e):
          return Result.error(e);
      }
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Creates a new version for a package.
  Future<Result<Version>> create({
    required int packageId,
    required String version,
    required String pubspecYaml,
    required String archiveUrl,
    required String archiveSha256,
    String? readme,
    String? changelog,
  }) async {
    try {
      // Validate semantic version
      try {
        semver.Version.parse(version);
      } catch (_) {
        return Result.error(
          VersionException('Invalid semantic version: $version'),
        );
      }

      // Check if version already exists
      final existingResult = await get(packageId: packageId, version: version);
      if (existingResult.isSuccess) {
        return Result.error(
          VersionException('Version already exists: $version'),
        );
      }

      final id = await _db.into(_db.versions).insert(
        VersionsCompanion.insert(
          packageId: packageId,
          version: version,
          pubspecYaml: pubspecYaml,
          archiveUrl: archiveUrl,
          archiveSha256: archiveSha256,
          readme: Value(readme),
          changelog: Value(changelog),
        ),
      );

      final query = _db.select(_db.versions)..where((v) => v.id.equals(id));
      final versionRow = await query.getSingle();

      return Result.ok(versionRow);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Retracts a version (soft delete).
  Future<Result<Version>> retract({
    required int packageId,
    required String version,
  }) async {
    try {
      final existingResult = await get(packageId: packageId, version: version);

      switch (existingResult) {
        case Ok(value: final existing):
          await (_db.update(_db.versions)
                ..where((v) => v.id.equals(existing.id)))
              .write(const VersionsCompanion(isRetracted: Value(true)));

          // Re-fetch the updated version
          final query = _db.select(_db.versions)
            ..where((v) => v.id.equals(existing.id));
          final updated = await query.getSingle();
          return Result.ok(updated);

        case Error(error: final e):
          return Result.error(e);
      }
    } on Exception catch (e) {
      return Result.error(e);
    }
  }
}
