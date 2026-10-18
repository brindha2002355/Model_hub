/// Base class for every error thrown by model_hub.
class ModelHubException implements Exception {
  /// Creates an exception for the model with the given [modelId].
  const ModelHubException(this.modelId, this.message);

  /// The id of the model that caused the error.
  final String modelId;

  /// A human readable description.
  final String message;

  @override
  String toString() => '$runtimeType($modelId): $message';
}

/// Thrown when the download fails (bad HTTP status, network error, timeout).
///
/// A partly downloaded file is kept, so the next `ensure()` call resumes it.
class ModelDownloadException extends ModelHubException {
  /// Creates a download exception.
  const ModelDownloadException(super.modelId, super.message, {this.statusCode});

  /// The HTTP status code, when the server answered with one.
  final int? statusCode;
}

/// Thrown when the downloaded file does not match the expected SHA-256.
///
/// The bad file is deleted, so the next `ensure()` call starts clean.
class ModelChecksumException extends ModelHubException {
  /// Creates a checksum exception.
  const ModelChecksumException(String modelId)
      : super(modelId, 'Downloaded file does not match the expected SHA-256.');
}

/// Thrown when `cancel()` stops a running download.
///
/// The partly downloaded file is kept for resuming later.
class ModelCancelledException extends ModelHubException {
  /// Creates a cancelled exception.
  const ModelCancelledException(String modelId)
      : super(modelId, 'Download was cancelled.');
}
