import 'dart:typed_data';

/// Abstract interface for blob storage.
///
/// This abstraction allows for different storage backends:
/// - [FileSystemStorage] for local filesystem (MVP)
/// - S3Storage for AWS S3 (Enterprise)
/// - GCSStorage for Google Cloud Storage (Enterprise)
abstract class BlobStorage {
  /// Stores bytes at the given path.
  Future<void> store(String path, Uint8List bytes);

  /// Retrieves bytes from the given path.
  ///
  /// Returns null if the path doesn't exist.
  Future<Uint8List?> retrieve(String path);

  /// Deletes the blob at the given path.
  Future<void> delete(String path);

  /// Checks if a blob exists at the given path.
  Future<bool> exists(String path);

  /// Lists all blobs with the given prefix.
  Future<List<String>> list(String prefix);
}
