import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

part 'database.g.dart';

// =============================================================================
// Tables
// =============================================================================

/// Users table for authentication and ownership.
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get email => text().unique()();
  TextColumn get token => text().unique()();
  TextColumn get displayName => text().nullable()();
  BoolColumn get isAdmin => boolean().withDefault(const Constant(false))();
  TextColumn get role => text()
      .withDefault(const Constant('user'))(); // 'super_admin', 'admin', 'user'
  TextColumn get status => text().withDefault(
      const Constant('active'))(); // 'active', 'suspended', 'deleted'
  DateTimeColumn get lastLoginAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

/// Packages table for package metadata.
class Packages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  TextColumn get description => text().nullable()();
  BoolColumn get isDiscontinued =>
      boolean().withDefault(const Constant(false))();
  TextColumn get replacedBy => text().nullable()();
  BoolColumn get isPrivate => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

/// Package uploaders (many-to-many relationship).
class PackageUploaders extends Table {
  IntColumn get packageId => integer().references(Packages, #id)();
  IntColumn get userId => integer().references(Users, #id)();

  @override
  Set<Column> get primaryKey => {packageId, userId};
}

/// Versions table for package versions.
class Versions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get packageId => integer().references(Packages, #id)();
  TextColumn get version => text()();
  TextColumn get pubspecYaml => text()();
  TextColumn get readme => text().nullable()();
  TextColumn get changelog => text().nullable()();
  TextColumn get archiveUrl => text()();
  TextColumn get archiveSha256 => text()();
  BoolColumn get isRetracted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {packageId, version},
      ];
}

/// Audit logs table for tracking all system actions.
class AuditLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().nullable()();
  TextColumn get action => text()(); // 'package.publish', 'user.create', etc.
  TextColumn get resourceType => text()(); // 'package', 'user', 'version'
  IntColumn get resourceId => integer().nullable()();
  TextColumn get ipAddress => text().nullable()();
  TextColumn get userAgent => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// =============================================================================
// Database
// =============================================================================

@DriftDatabase(tables: [Users, Packages, PackageUploaders, Versions, AuditLogs])
class DarktarDatabase extends _$DarktarDatabase {
  DarktarDatabase(super.e);

  /// Creates a database from a file path.
  factory DarktarDatabase.fromPath(String path) {
    return DarktarDatabase(_openConnection(path));
  }

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          // Add new columns to Users table
          await m.addColumn(users, users.role);
          await m.addColumn(users, users.status);
          await m.addColumn(users, users.lastLoginAt);

          // Add isPrivate to Packages table
          await m.addColumn(packages, packages.isPrivate);

          // Create AuditLogs table
          await m.createTable(auditLogs);

          // Note: Existing users will have role='user' by default.
          // To migrate isAdmin to role, run this manually:
          // UPDATE users SET role = CASE WHEN is_admin = 1 THEN 'admin' ELSE 'user' END
        }
      },
    );
  }
}

LazyDatabase _openConnection(String path) {
  return LazyDatabase(() async {
    final dbFolder = File(path).parent;
    if (!await dbFolder.exists()) {
      await dbFolder.create(recursive: true);
    }
    final file = File(p.join(dbFolder.path, p.basename(path)));
    return NativeDatabase.createInBackground(file);
  });
}
