import 'dart:io';

/// A model file found on the device.
class ModelInfo {
  /// Creates a model info entry.
  const ModelInfo({
    required this.id,
    required this.version,
    required this.file,
    required this.sizeBytes,
    required this.isPartial,
  });

  /// Model id.
  final String id;

  /// Model version.
  final int version;

  /// The file on disk.
  final File file;

  /// Current size in bytes.
  final int sizeBytes;

  /// `true` when the download is not finished yet (a `.part` file).
  final bool isPartial;

  @override
  String toString() =>
      'ModelInfo($id v$version, $sizeBytes bytes, partial: $isPartial)';
}
