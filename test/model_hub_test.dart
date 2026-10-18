import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:model_hub/model_hub.dart';

Uint8List makeBytes(int n) =>
    Uint8List.fromList(List.generate(n, (i) => i % 251));

String hashOf(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  late Directory tmp;
  final data = makeBytes(1000);

  ModelSpec spec({int version = 1, String? hash}) => ModelSpec(
        id: 'm',
        url: 'https://example.com/m.bin',
        sha256: hash ?? hashOf(data),
        version: version,
      );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('model_hub_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('downloads, verifies and returns the file', () async {
    final hub = ModelHub(
      baseDirectory: tmp,
      client: MockClient((_) async => http.Response.bytes(data, 200)),
    );
    final progress = <double>[];

    final file = await hub.ensure(spec(), onProgress: progress.add);

    expect(await file.readAsBytes(), data);
    expect(file.path.endsWith('m_v1.model'), isTrue);
    expect(progress.last, 1.0);
  });

  test('second call uses the saved file and makes no request', () async {
    var calls = 0;
    final hub = ModelHub(
      baseDirectory: tmp,
      client: MockClient((_) async {
        calls++;
        return http.Response.bytes(data, 200);
      }),
    );

    await hub.ensure(spec());
    await hub.ensure(spec());

    expect(calls, 1);
    expect(await hub.isDownloaded(spec()), isTrue);
  });

  test('wrong hash throws and deletes the bad file', () async {
    final hub = ModelHub(
      baseDirectory: tmp,
      client: MockClient((_) async => http.Response.bytes(data, 200)),
    );

    await expectLater(
      hub.ensure(spec(hash: hashOf([1, 2, 3]))),
      throwsA(isA<ModelChecksumException>()),
    );
    expect(await hub.list(), isEmpty);
  });

  test('resumes from a .part file with a Range header', () async {
    final modelDir = Directory('${tmp.path}/models')..createSync();
    File('${modelDir.path}/m_v1.model.part')
        .writeAsBytesSync(data.sublist(0, 400));

    String? rangeHeader;
    final hub = ModelHub(
      baseDirectory: tmp,
      client: MockClient((request) async {
        rangeHeader = request.headers['Range'];
        return http.Response.bytes(data.sublist(400), 206);
      }),
    );

    final file = await hub.ensure(spec());

    expect(rangeHeader, 'bytes=400-');
    expect(await file.readAsBytes(), data);
  });

  test('restarts when the server ignores Range (status 200)', () async {
    final modelDir = Directory('${tmp.path}/models')..createSync();
    File('${modelDir.path}/m_v1.model.part')
        .writeAsBytesSync(data.sublist(0, 400));

    final hub = ModelHub(
      baseDirectory: tmp,
      client: MockClient((_) async => http.Response.bytes(data, 200)),
    );

    final file = await hub.ensure(spec());

    expect(await file.readAsBytes(), data);
  });

  test('deletes older versions of the same model', () async {
    final hub = ModelHub(
      baseDirectory: tmp,
      client: MockClient((_) async => http.Response.bytes(data, 200)),
    );

    await hub.ensure(spec(version: 1));
    await hub.ensure(spec(version: 2));

    final models = await hub.list();
    expect(models.length, 1);
    expect(models.single.version, 2);
  });

  test('bad HTTP status throws ModelDownloadException', () async {
    final hub = ModelHub(
      baseDirectory: tmp,
      client: MockClient((_) async => http.Response('nope', 404)),
    );

    await expectLater(
      hub.ensure(spec()),
      throwsA(isA<ModelDownloadException>()
          .having((e) => e.statusCode, 'statusCode', 404)),
    );
  });

  test('two simultaneous calls share one download', () async {
    var calls = 0;
    final hub = ModelHub(
      baseDirectory: tmp,
      client: MockClient((_) async {
        calls++;
        return http.Response.bytes(data, 200);
      }),
    );

    await Future.wait([hub.ensure(spec()), hub.ensure(spec())]);

    expect(calls, 1);
  });

  test('cancel stops the download and keeps the .part file', () async {
    final hub = ModelHub(
      baseDirectory: tmp,
      client: MockClient.streaming((request, body) async {
        Stream<List<int>> chunks() async* {
          for (var i = 0; i < 10; i++) {
            yield data.sublist(i * 100, (i + 1) * 100);
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
        }

        return http.StreamedResponse(chunks(), 200, contentLength: data.length);
      }),
    );

    await expectLater(
      hub.ensure(spec(), onProgress: (_) => hub.cancel('m')),
      throwsA(isA<ModelCancelledException>()),
    );

    final models = await hub.list();
    expect(models.single.isPartial, isTrue);
  });

  test('list and delete work', () async {
    final hub = ModelHub(
      baseDirectory: tmp,
      client: MockClient((_) async => http.Response.bytes(data, 200)),
    );
    await hub.ensure(spec());

    expect((await hub.list()).single.sizeBytes, data.length);
    expect(await hub.delete('m'), isTrue);
    expect(await hub.list(), isEmpty);
    expect(await hub.delete('m'), isFalse);
  });

  test('invalid id is rejected', () {
    final hub = ModelHub(baseDirectory: tmp);
    expect(
      () => hub.ensure(const ModelSpec(id: '../x', url: 'u', sha256: 'h')),
      throwsArgumentError,
    );
  });
}
