import 'package:drift/drift.dart';

import '../database.dart';
import '../result.dart';

/// Exception for audit log-related errors.
class AuditLogException implements Exception {
  const AuditLogException(this.message);
  final String message;

  @override
  String toString() => 'AuditLogException: $message';
}

/// Repository for audit log operations.
class AuditLogRepository {
  const AuditLogRepository(this._db);

  final DarktarDatabase _db;

  /// Creates a new audit log entry.
  Future<Result<AuditLog>> create({
    int? userId,
    required String action,
    required String resourceType,
    int? resourceId,
    String? ipAddress,
    String? userAgent,
  }) async {
    try {
      final id = await _db.into(_db.auditLogs).insert(
        AuditLogsCompanion.insert(
          userId: Value(userId),
          action: action,
          resourceType: resourceType,
          resourceId: Value(resourceId),
          ipAddress: Value(ipAddress),
          userAgent: Value(userAgent),
        ),
      );

      final query = _db.select(_db.auditLogs)..where((al) => al.id.equals(id));
      final log = await query.getSingle();

      return Result.ok(log);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Lists audit logs with optional filters.
  Future<Result<List<AuditLog>>> list({
    int? limit,
    int? offset,
    int? userId,
    String? action,
    String? resourceType,
    int? resourceId,
  }) async {
    try {
      var query = _db.select(_db.auditLogs);

      if (userId != null) {
        query = query..where((al) => al.userId.equals(userId));
      }

      if (action != null) {
        query = query..where((al) => al.action.equals(action));
      }

      if (resourceType != null) {
        query = query..where((al) => al.resourceType.equals(resourceType));
      }

      if (resourceId != null) {
        query = query..where((al) => al.resourceId.equals(resourceId));
      }

      query = query..orderBy([(al) => OrderingTerm.desc(al.createdAt)]);

      if (limit != null) {
        query = query..limit(limit, offset: offset);
      }

      final logs = await query.get();
      return Result.ok(logs);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Gets audit logs for a specific resource.
  Future<Result<List<AuditLog>>> getForResource({
    required String resourceType,
    required int resourceId,
    int? limit,
  }) async {
    return list(
      resourceType: resourceType,
      resourceId: resourceId,
      limit: limit,
    );
  }

  /// Gets audit logs for a specific user.
  Future<Result<List<AuditLog>>> getForUser(int userId, {int? limit}) async {
    return list(userId: userId, limit: limit);
  }
}
