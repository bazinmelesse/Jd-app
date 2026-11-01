import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/engine/engine_bridge.dart';
import '../services/youtube_web_search.dart';

/// Web version: shows [child] once a YouTube key is saved, and the steps
/// to get one before that. On Android it just shows [child].
class YoutubeKeyGate extends StatelessWidget {
  final Widget child;
  const YoutubeKeyGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!isWebEngine || context.watch<YoutubeKey>().hasKey) return child;
    return const YoutubeKeySetup();
  }
}

class YoutubeKeySetup extends StatefulWidget {
  const YoutubeKeySetup({super.key});

  @override
  State<YoutubeKeySetup> createState() => _YoutubeKeySetupState();
}

class _YoutubeKeySetupState extends State<YoutubeKeySetup> {
  final _field = TextEditingController();
  bool _saving = false;
  String? _error;

  static const _consoleUrl =
      'https://console.cloud.google.com/apis/library/youtube.googleapis.com';

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<YoutubeKey>().save(_field.text);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const step = TextStyle(height: 1.45);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Turn on YouTube search',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
            'In a browser, YouTube search needs a free key from your Google '
            'account. It takes about 3 minutes, once. The key stays in this '
            'browser.',
            style: step),
        const SizedBox(height: 16),
        const Text('1. Open the Google Cloud page below and sign in.',
            style: step),
        Row(
          children: [
            Expanded(
              child: SelectableText(_consoleUrl,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 13)),
            ),
            IconButton(
              tooltip: 'Copy link',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () =>
                  Clipboard.setData(const ClipboardData(text: _consoleUrl)),
            ),
          ],
        ),
        const Text(
            '2. If asked, create a project (any name), then tap ENABLE on '
            '"YouTube Data API v3".\n'
            '3. Go to Credentials, tap "+ Create credentials", then "API key".\n'
            '4. Copy the key (it starts with AIza) and paste it here.',
            style: step),
        const SizedBox(height: 16),
        TextField(
          controller: _field,
          decoration: InputDecoration(
            labelText: 'YouTube API key',
            hintText: 'AIza...',
            border: const OutlineInputBorder(),
            errorText: _error,
            errorMaxLines: 3,
          ),
          autocorrect: false,
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Checking...' : 'Save key'),
        ),
        const SizedBox(height: 16),
        const Text(
            'The free key allows about 100 searches a day. Playing videos '
            'doesn\'t use it up.',
            style: TextStyle(fontSize: 12, color: Colors.white60)),
      ],
    );
  }
}
