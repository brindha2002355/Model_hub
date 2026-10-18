# model_hub

Download, verify, resume and cache large on-device AI model files
(TFLite, ONNX, GGUF, anything) with one line of code.

Keep your app small: do not bundle a 100 MB model in the APK. Download it
when the user first needs it, and let `model_hub` handle the hard parts.

## Features

- Resume interrupted downloads (HTTP `Range`).
- SHA-256 check, so a corrupt file is never used.
- Cached: a model that is already on the device is not downloaded again.
- Versioning: a new `version` removes the old file automatically.
- Progress callback, `cancel()`, `list()`, `delete()`.
- Custom headers (for example a Hugging Face token).
- Works with any server. It does not run the model, so use it together with
  `tflite_flutter`, `onnxruntime`, etc.

## Usage

```dart
import 'package:model_hub/model_hub.dart';

final hub = ModelHub();

final file = await hub.ensure(
  const ModelSpec(
    id: 'plant_disease',
    url: 'https://example.com/plant_disease.tflite',
    sha256: 'PUT_THE_REAL_SHA256_HERE',
    version: 1,
  ),
  onProgress: (p) => print('${(p * 100).toInt()}%'),
);

// file is ready. Give it to your AI library:
// final interpreter = Interpreter.fromFile(file);
```

Get the SHA-256 of your model file with:

```bash
sha256sum plant_disease.tflite        # Linux / macOS
certutil -hashfile plant_disease.tflite SHA256   # Windows
```

## Errors

| Exception | Meaning | What happens to the file |
|---|---|---|
| `ModelDownloadException` | Network error, timeout or bad status | `.part` file kept, next call resumes |
| `ModelChecksumException` | File does not match the SHA-256 | file deleted, next call starts clean |
| `ModelCancelledException` | You called `cancel()` | `.part` file kept, next call resumes |

## Notes

- Resume needs a server that supports `Range` (Hugging Face and most CDNs do).
  If not, the download simply restarts.
- Not included yet: Wi-Fi-only mode and free-space check.
- Native platforms only (Android, iOS, desktop). Web is not supported because
  it needs the file system.

## License

MIT
