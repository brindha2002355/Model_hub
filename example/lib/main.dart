import 'package:flutter/material.dart';
import 'package:model_hub/model_hub.dart';

void main() => runApp(const MaterialApp(home: ExamplePage()));

class ExamplePage extends StatefulWidget {
  const ExamplePage({super.key});

  @override
  State<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> {
  final hub = ModelHub();

  // Replace with your own model link and SHA-256.
  final spec = const ModelSpec(
    id: 'demo_model',
    url: 'https://example.com/model.tflite',
    sha256: 'PUT_THE_REAL_SHA256_HERE',
    version: 1,
  );

  double progress = 0;
  String status = 'Not downloaded';
  bool busy = false;

  Future<void> download() async {
    setState(() {
      busy = true;
      status = 'Downloading...';
    });
    try {
      final file = await hub.ensure(
        spec,
        onProgress: (p) => setState(() => progress = p),
      );
      setState(() => status = 'Ready: ${file.path}');
    } on ModelCancelledException {
      setState(() => status = 'Cancelled. Press download to resume.');
    } on ModelHubException catch (e) {
      setState(() => status = 'Error: ${e.message}');
    } finally {
      setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    hub.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('model_hub example')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 12),
            Text('${(progress * 100).toInt()}%'),
            const SizedBox(height: 12),
            Text(status),
            const SizedBox(height: 24),
            Row(
              children: [
                ElevatedButton(
                  onPressed: busy ? null : download,
                  child: const Text('Download'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: busy ? () => hub.cancel(spec.id) : null,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
