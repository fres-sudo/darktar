import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:yaml/yaml.dart';

import 'package:darktar/api/middleware/auth.dart';
import 'package:darktar/config/env.dart';
import 'package:darktar/data/database.dart';
import 'package:darktar/data/repositories/audit_log_repository.dart';
import 'package:darktar/data/repositories/package_repository.dart';
import 'package:darktar/data/repositories/package_uploader_repository.dart';
import 'package:darktar/data/repositories/version_repository.dart';
import 'package:darktar/data/result.dart';
import 'package:darktar/jobs/doc_generator_job.dart';
import 'package:darktar/jobs/job_queue.dart';
import 'package:darktar/storage/blob_storage.dart';

/// Handlers for the Pub API package endpoints.
class PackageHandlers {
  PackageHandlers({
    required this.db,
    required this.storage,
    required this.config,
    required this.jobQueue,
  })  : packageRepository = PackageRepository(db),
        versionRepository = VersionRepository(db),
        packageUploaderRepository = PackageUploaderRepository(db),
        auditLogRepository = AuditLogRepository(db);

  final DarktarDatabase db;
  final BlobStorage storage;
  final EnvConfig config;
  final JobQueue jobQueue;
  final PackageRepository packageRepository;
  final VersionRepository versionRepository;
  final PackageUploaderRepository packageUploaderRepository;
  final AuditLogRepository auditLogRepository;

  /// Registers routes on the provided router.
  void registerRoutes(Router router) {
    // Pub API v2 endpoints
    router.get('/api/packages/<name>', getPackage);
    router.get('/api/packages/<name>/versions/<version>', getVersion);

    // Archive download
    router.get('/packages/<name>/versions/<version>.tar.gz', downloadArchive);

    // Publishing (requires auth)
    router.get('/api/packages/versions/new', getUploadUrl);
    router.post('/api/packages/versions/newUpload', uploadPackage);
    router.get('/api/packages/versions/newUploadFinish', finishUpload);
  }

  /// Helper function to log package actions.
  Future<void> _logAction({
    required Request request,
    required String action,
    required String resourceType,
    int? resourceId,
  }) async {
    final user = request.user;
    await auditLogRepository.create(
      userId: user?.id,
      action: action,
      resourceType: resourceType,
      resourceId: resourceId,
      ipAddress: request.headers['x-forwarded-for'] ??
          request.headers['x-real-ip'] ??
          'unknown',
      userAgent: request.headers['user-agent'],
    );
  }

  /// GET /api/packages/<name>
  ///
  /// Returns package metadata with all versions.
  Future<Response> getPackage(Request request, String name) async {
    final packageResult = await packageRepository.getByName(name);

    return switch (packageResult) {
      Ok(value: final package) => () async {
          final versionsResult =
              await versionRepository.listForPackage(package.id);

          return switch (versionsResult) {
            Ok(value: final versions) => Response.ok(
                jsonEncode(_buildPackageResponse(package, versions)),
                headers: {'Content-Type': 'application/json'},
              ),
            Error() => Response.internalServerError(
                body: '{"error":"Failed to fetch versions"}',
                headers: {'Content-Type': 'application/json'},
              ),
          };
        }(),
      Error() => Response.notFound(
          '{"error":"Package not found: $name"}',
          headers: {'Content-Type': 'application/json'},
        ),
    };
  }

  /// GET /api/packages/<name>/versions/<version>
  ///
  /// Returns metadata for a specific version.
  Future<Response> getVersion(
    Request request,
    String name,
    String version,
  ) async {
    final packageResult = await packageRepository.getByName(name);

    return switch (packageResult) {
      Ok(value: final package) => () async {
          final versionResult = await versionRepository.get(
            packageId: package.id,
            version: version,
          );

          return switch (versionResult) {
            Ok(value: final ver) => Response.ok(
                jsonEncode(_buildVersionResponse(package.name, ver)),
                headers: {'Content-Type': 'application/json'},
              ),
            Error() => Response.notFound(
                '{"error":"Version not found: $name@$version"}',
                headers: {'Content-Type': 'application/json'},
              ),
          };
        }(),
      Error() => Response.notFound(
          '{"error":"Package not found: $name"}',
          headers: {'Content-Type': 'application/json'},
        ),
    };
  }

  /// GET /packages/<name>/versions/<version>.tar.gz
  ///
  /// Downloads the package archive.
  Future<Response> downloadArchive(
    Request request,
    String name,
    String version,
  ) async {
    final archivePath = _getArchivePath(name, version);
    final bytes = await storage.retrieve(archivePath);

    if (bytes == null) {
      return Response.notFound(
        '{"error":"Archive not found: $name@$version"}',
        headers: {'Content-Type': 'application/json'},
      );
    }

    return Response.ok(
      bytes,
      headers: {
        'Content-Type': 'application/octet-stream',
        'Content-Disposition': 'attachment; filename="$name-$version.tar.gz"',
      },
    );
  }

  /// GET /api/packages/versions/new
  ///
  /// Returns the upload URL for publishing.
  Future<Response> getUploadUrl(Request request) async {
    if (!request.isAuthenticated) {
      return Response.unauthorized(
        '{"error":"Authentication required"}',
        headers: {'Content-Type': 'application/json'},
      );
    }

    final baseUrl = config.effectiveBaseUrl;

    return Response.ok(
      jsonEncode({
        'url': '$baseUrl/api/packages/versions/newUpload',
        'fields': <String, String>{},
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// POST /api/packages/versions/newUpload
  ///
  /// Handles the package upload.
  Future<Response> uploadPackage(Request request) async {
    if (!request.isAuthenticated) {
      return Response.unauthorized(
        '{"error":"Authentication required"}',
        headers: {'Content-Type': 'application/json'},
      );
    }

    try {
      // Read the uploaded file
      final bytes = await request.read().expand((e) => e).toList();
      final archive = Uint8List.fromList(bytes);

      // Validate and extract pubspec
      final validationResult = await _validateArchive(archive);

      return switch (validationResult) {
        Ok(value: final pubspec) => () async {
            final name = pubspec['name'] as String;
            final version = pubspec['version'] as String;
            final user = request.user;
            if (user == null) {
              return Response.unauthorized(
                '{"error":"Authentication required"}',
                headers: {'Content-Type': 'application/json'},
              );
            }

            // Get or create the package
            var packageResult = await packageRepository.getByName(name);
            Package package;
            bool isNewPackage = false;

            switch (packageResult) {
              case Ok(value: final existingPackage):
                package = existingPackage;
                // Check if user can publish to this package
                final isAdmin = user.isAdmin ||
                    user.role == 'admin' ||
                    user.role == 'super_admin';
                if (!isAdmin) {
                  final canPublishResult =
                      await packageUploaderRepository.canPublish(
                    packageId: package.id,
                    userId: user.id,
                  );
                  final canPublish = switch (canPublishResult) {
                    Ok(value: final can) => can,
                    Error() => false,
                  };
                  if (!canPublish) {
                    return Response.forbidden(
                      '{"error":"You do not have permission to publish to this package"}',
                      headers: {'Content-Type': 'application/json'},
                    );
                  }
                }
              case Error():
                // Create new package
                final createResult = await packageRepository.create(
                  name: name,
                  description: pubspec['description'] as String?,
                );
                switch (createResult) {
                  case Ok(value: final newPackage):
                    package = newPackage;
                    isNewPackage = true;
                  case Error(error: final e):
                    return Response.internalServerError(
                      body: '{"error":"Failed to create package: $e"}',
                      headers: {'Content-Type': 'application/json'},
                    );
                }
            }

            // Calculate SHA256
            final sha256Hash = sha256.convert(archive).toString();

            // Store the archive
            final archivePath = _getArchivePath(name, version);
            await storage.store(archivePath, archive);

            // Add user as uploader if this is a new package
            if (isNewPackage) {
              await packageUploaderRepository.addUploader(
                packageId: package.id,
                userId: user.id,
              );
            }

            // Create the version
            final archiveUrl =
                '${config.effectiveBaseUrl}/packages/$name/versions/$version.tar.gz';

            final versionResult = await versionRepository.create(
              packageId: package.id,
              version: version,
              pubspecYaml: _extractPubspecYaml(archive) ?? '',
              archiveUrl: archiveUrl,
              archiveSha256: sha256Hash,
              readme: _extractFile(archive, 'README.md'),
              changelog: _extractFile(archive, 'CHANGELOG.md'),
            );

            // Enqueue documentation generation
            if (versionResult.isSuccess) {
              jobQueue.enqueue(
                DocGeneratorJob(
                  packageName: name,
                  version: version,
                  storage: storage,
                  docsOutputPath: config.docsPath,
                  themeDir: 'lib/web/static/css',
                ),
              );
            }

            return switch (versionResult) {
              Ok() => () async {
                  // Log the action
                  await _logAction(
                    request: request,
                    action: isNewPackage
                        ? 'package.publish'
                        : 'package.version.publish',
                    resourceType: isNewPackage ? 'package' : 'version',
                    resourceId: package.id,
                  );

                  return Response.ok(
                    jsonEncode({
                      'success': {
                        'message': 'Successfully uploaded $name@$version',
                      },
                    }),
                    headers: {'Content-Type': 'application/json'},
                  );
                }(),
              Error(error: final e) => Response(
                  HttpStatus.conflict,
                  body: '{"error":"${e.toString()}"}',
                  headers: {'Content-Type': 'application/json'},
                ),
            };
          }(),
        Error(error: final e) => Response.badRequest(
            body: '{"error":"Invalid package: ${e.toString()}"}',
            headers: {'Content-Type': 'application/json'},
          ),
      } as Response;
    } on Exception catch (e) {
      return Response.internalServerError(
        body: '{"error":"Upload failed: $e"}',
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /api/packages/versions/newUploadFinish
  ///
  /// Finalizes the upload (for compatibility).
  Future<Response> finishUpload(Request request) async {
    return Response.ok(
      jsonEncode({
        'success': {'message': 'Upload finalized'}
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // =========================================================================
  // Private helpers
  // =========================================================================

  /// Builds the Pub API response for a package.
  Map<String, dynamic> _buildPackageResponse(
    Package package,
    List<Version> versions,
  ) {
    return {
      'name': package.name,
      'isDiscontinued': package.isDiscontinued,
      if (package.replacedBy != null) 'replacedBy': package.replacedBy,
      'versions':
          versions.map((v) => _buildVersionResponse(package.name, v)).toList(),
    };
  }

  /// Builds the Pub API response for a version.
  Map<String, dynamic> _buildVersionResponse(
      String packageName, Version version) {
    return {
      'version': version.version,
      'pubspec': _parsePubspec(version.pubspecYaml),
      'archive_url': version.archiveUrl,
      'archive_sha256': version.archiveSha256,
      'published': version.createdAt.toUtc().toIso8601String(),
      if (version.isRetracted) 'retracted': true,
    };
  }

  /// Parses pubspec YAML to a map.
  Map<String, dynamic> _parsePubspec(String yaml) {
    try {
      final doc = loadYaml(yaml);
      return Map<String, dynamic>.from(doc as Map);
    } catch (_) {
      return {};
    }
  }

  /// Validates the uploaded archive.
  Future<Result<Map<String, dynamic>>> _validateArchive(Uint8List bytes) async {
    try {
      final gzDecoded = GZipDecoder().decodeBytes(bytes);
      final archive = TarDecoder().decodeBytes(gzDecoded);

      // Find pubspec.yaml
      ArchiveFile? pubspecFile;
      for (final file in archive.files) {
        if (file.name == 'pubspec.yaml' ||
            file.name.endsWith('/pubspec.yaml')) {
          pubspecFile = file;
          break;
        }
      }

      if (pubspecFile == null) {
        return const Result.error(
          FormatException('pubspec.yaml not found in archive'),
        );
      }

      final pubspecContent = utf8.decode(pubspecFile.content as List<int>);
      final pubspec = loadYaml(pubspecContent);

      final name = pubspec['name'];
      final version = pubspec['version'];

      if (name == null || name is! String) {
        return const Result.error(
          FormatException('Missing or invalid "name" in pubspec.yaml'),
        );
      }

      if (version == null || version is! String) {
        return const Result.error(
          FormatException('Missing or invalid "version" in pubspec.yaml'),
        );
      }

      // Validate package name format
      if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
        return Result.error(
          FormatException('Invalid package name: $name'),
        );
      }

      return Result.ok(Map<String, dynamic>.from(pubspec as Map));
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Extracts pubspec.yaml content from archive.
  String? _extractPubspecYaml(Uint8List bytes) {
    try {
      final gzDecoded = GZipDecoder().decodeBytes(bytes);
      final archive = TarDecoder().decodeBytes(gzDecoded);

      for (final file in archive.files) {
        if (file.name == 'pubspec.yaml' ||
            file.name.endsWith('/pubspec.yaml')) {
          return utf8.decode(file.content as List<int>);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Extracts a file by name from the archive.
  String? _extractFile(Uint8List bytes, String filename) {
    try {
      final gzDecoded = GZipDecoder().decodeBytes(bytes);
      final archive = TarDecoder().decodeBytes(gzDecoded);

      for (final file in archive.files) {
        if (file.name == filename || file.name.endsWith('/$filename')) {
          return utf8.decode(file.content as List<int>);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Gets the storage path for an archive.
  String _getArchivePath(String name, String version) {
    return 'packages/$name/$version.tar.gz';
  }
}
