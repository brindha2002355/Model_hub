## 0.1.0

- Initial release.
- `ModelHub.ensure()` downloads, verifies (SHA-256) and caches a model file.
- Resume support for interrupted downloads (HTTP Range).
- Old versions of the same model are deleted automatically.
- `cancel`, `isDownloaded`, `list`, `delete` and `deleteAll` helpers.
- Custom headers (for example a Hugging Face token).
