/// Describes one model file: where to get it and how to verify it.
class ModelSpec {
  /// Creates a model description.
  ///
  /// [id] may only contain letters, digits, `_` and `-` because it is used
  /// in file names.
  const ModelSpec({
    required this.id,
    required this.url,
    required this.sha256,
    this.version = 1,
    this.headers = const {},
  }) : assert(version > 0, 'version must be greater than 0');

  /// Short unique name, for example `plant_disease`.
  final String id;

  /// Direct download link.
  final String url;

  /// Expected SHA-256 of the complete file, as a hex string.
  final String sha256;

  /// Increase this number when you publish a new model file.
  /// Older versions of the same [id] are deleted automatically.
  final int version;

  /// Extra HTTP headers, for example `{'Authorization': 'Bearer hf_...'}`
  /// for a private Hugging Face model.
  final Map<String, String> headers;

  /// [sha256] in lower case, used for comparing.
  String get expectedHash => sha256.trim().toLowerCase();

  /// Whether [id] is safe to use in a file name.
  bool get hasValidId => RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id);
}
