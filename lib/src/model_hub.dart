import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'exceptions.dart';
import 'model_info.dart';
import 'model_spec.dart';

/// Called while downloading. [progress] goes from 0.0 to 1.0.
typedef ProgressCallback = void Function(double progress);

/// Downloads, verifies and caches model files.
///
/// ```dart
/// final hub = ModelHub();
/// final file = await hub.ensure(
///   const ModelSpec(id: 'mobilenet', url: '...', sha256: '...'),
///   onProgress: (p) => print('${(p * 100).toInt()}%'),
/// );
/// ```
class ModelHub {
  /// Creates a hub.
  ///
  /// [client] and [baseDirectory] are mainly for tests. By default the models
  /// are stored in the app support directory.
  /// [timeout] is the longest wait for the server (or between two chunks).
  ModelHub({
    http.Client? client,
    Directory? baseDirectory,
    this.timeout = const Duration(seconds: 30),
  })  : _client = client ?? http.Client(),
        _baseDirectory = baseDirectory;

  final http.Client _client;
  final Directory? _baseDirectory;

  /// Longest wait for the server response or between two data chunks.
  final Duration timeout;

  final Map<String, Future<File>> _inFlight = {};
  final Set<String> _cancelRequests = {};

  /// Makes sure the model file is on the device and correct, then returns it.
  ///
  /// 1. A saved file with the right hash is returned at once.
  /// 2. Otherwise other versions of the same model are deleted.
  /// 3. The file is downloaded, resuming a `.part` file when possible.
  /// 4. The SHA-256 is checked, then the file gets its final name.
  ///
  /// Calling this twice for the same model at the same time shares one
  /// download.
  ///
  /// Throws [ModelDownloadException], [ModelChecksumException] or
  /// [ModelCancelledException].
  Future<File> ensure(ModelSpec spec, {ProgressCallback? onProgress}) {
    if (!spec.hasValidId) {
      throw ArgumentError.value(
        spec.id,
        'spec.id',
        'Only letters, digits, "_" and "-" are allowed.',
      );
    }
    final running = _inFlight[spec.id];
    if (running != null) return running;

    _cancelRequests.remove(spec.id);
    final future = _ensure(spec, onProgress).whenComplete(() {
      _inFlight.remove(spec.id);
      _cancelRequests.remove(spec.id);
    });
    _inFlight[spec.id] = future;
    return future;
  }

  /// Stops a running download of the model with [id].
  ///
  /// The partly downloaded file is kept. Returns `false` when nothing was
  /// running.
  bool cancel(String id) {
    if (!_inFlight.containsKey(id)) return false;
    _cancelRequests.add(id);
    return true;
  }

  /// Whether the complete, correct file for [spec] is already on the device.
  Future<bool> isDownloaded(ModelSpec spec) async {
    final file = _fileFor(await _modelDir(), spec);
    return await file.exists() && await _sha256Of(file) == spec.expectedHash;
  }

  /// Lists every model file (and unfinished download) on the device.
  Future<List<ModelInfo>> list() async {
    final dir = await _modelDir();
    final result = <ModelInfo>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final match = _fileName.firstMatch(_nameOf(entity));
      if (match == null) continue;
      result.add(ModelInfo(
        id: match.group(1)!,
        version: int.parse(match.group(2)!),
        file: entity,
        sizeBytes: await entity.length(),
        isPartial: match.group(3) != null,
      ));
    }
    result.sort((a, b) => a.id.compareTo(b.id));
    return result;
  }

  /// Deletes every file of the model with [id]. Returns `true` if any file
  /// was deleted.
  Future<bool> delete(String id) async {
    final dir = await _modelDir();
    var deleted = false;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final match = _fileName.firstMatch(_nameOf(entity));
      if (match != null && match.group(1) == id) {
        await entity.delete();
        deleted = true;
      }
    }
    return deleted;
  }

  /// Deletes all models and unfinished downloads.
  Future<void> deleteAll() async {
    final dir = await _modelDir();
    await for (final entity in dir.list()) {
      if (entity is File && _fileName.hasMatch(_nameOf(entity))) {
        await entity.delete();
      }
    }
  }

  /// Closes the HTTP client. Call it when you no longer need the hub.
  void dispose() => _client.close();

  // ---------------------------------------------------------------------------

  static final RegExp _fileName = RegExp(r'^(.+)_v(\d+)\.model(\.part)?$');

  Future<File> _ensure(ModelSpec spec, ProgressCallback? onProgress) async {
    final dir = await _modelDir();
    final file = _fileFor(dir, spec);
    final part = File('${file.path}.part');

    // 1. Already saved and correct?
    if (await file.exists()) {
      if (await _sha256Of(file) == spec.expectedHash) {
        onProgress?.call(1.0);
        return file;
      }
      await file.delete();
    }

    // 2. Remove other versions of this model.
    await _deleteOtherVersions(dir, spec);

    // 3. Download (resumes a .part file when it exists).
    await _download(spec, part, onProgress);

    // 4. Verify, then give the file its final name.
    if (await _sha256Of(part) != spec.expectedHash) {
      await part.delete();
      throw ModelChecksumException(spec.id);
    }
    await part.rename(file.path);
    onProgress?.call(1.0);
    return file;
  }

  Future<void> _download(
    ModelSpec spec,
    File part,
    ProgressCallback? onProgress,
  ) async {
    final existing = await part.exists() ? await part.length() : 0;

    final request = http.Request('GET', Uri.parse(spec.url))
      ..headers.addAll(spec.headers);
    if (existing > 0) request.headers['Range'] = 'bytes=$existing-';

    try {
      final response = await _client.send(request).timeout(timeout);
      final status = response.statusCode;

      // 416: the file on disk already covers the whole file.
      // The hash check after this decides if it is correct.
      if (status == 416 && existing > 0) {
        await response.stream.drain<void>();
        return;
      }
      if (status != 200 && status != 206) {
        await response.stream.drain<void>();
        throw ModelDownloadException(
          spec.id,
          'Server answered with status $status.',
          statusCode: status,
        );
      }

      // 206: the server accepted the resume. 200: it sent the whole file.
      final resumed = status == 206 && existing > 0;
      var received = resumed ? existing : 0;
      final length = response.contentLength;
      final total = length == null ? null : length + (resumed ? existing : 0);

      final sink = part.openWrite(
        mode: resumed ? FileMode.append : FileMode.write,
      );
      try {
        await for (final chunk in response.stream.timeout(timeout)) {
          if (_cancelRequests.contains(spec.id)) {
            throw ModelCancelledException(spec.id);
          }
          sink.add(chunk);
          received += chunk.length;
          if (total != null && total > 0) {
            onProgress?.call((received / total).clamp(0.0, 1.0));
          }
        }
      } finally {
        await sink.close();
      }
    } on ModelHubException {
      rethrow;
    } on TimeoutException {
      throw ModelDownloadException(spec.id, 'Connection timed out.');
    } on SocketException catch (e) {
      throw ModelDownloadException(spec.id, 'Network error: ${e.message}');
    } on http.ClientException catch (e) {
      throw ModelDownloadException(spec.id, 'Network error: ${e.message}');
    }
  }

  Future<String> _sha256Of(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  Future<Directory> _modelDir() async {
    final base = _baseDirectory ?? await getApplicationSupportDirectory();
    return Directory('${base.path}/models').create(recursive: true);
  }

  File _fileFor(Directory dir, ModelSpec spec) =>
      File('${dir.path}/${spec.id}_v${spec.version}.model');

  String _nameOf(FileSystemEntity e) => e.uri.pathSegments.last;

  Future<void> _deleteOtherVersions(Directory dir, ModelSpec spec) async {
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final match = _fileName.firstMatch(_nameOf(entity));
      if (match == null) continue;
      final sameModel = match.group(1) == spec.id;
      final otherVersion = int.parse(match.group(2)!) != spec.version;
      if (sameModel && otherVersion) await entity.delete();
    }
  }
}
