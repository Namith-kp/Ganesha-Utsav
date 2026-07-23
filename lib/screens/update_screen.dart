import 'package:flutter/material.dart';
import '../services/update_service.dart';

class UpdateWrapper extends StatefulWidget {
  final Widget child;
  const UpdateWrapper({super.key, required this.child});

  @override
  State<UpdateWrapper> createState() => _UpdateWrapperState();
}

class _UpdateWrapperState extends State<UpdateWrapper> {
  bool _checking = true;
  String? _downloadUrl;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final url = await UpdateService.checkForUpdate();
    if (mounted) {
      setState(() {
        _downloadUrl = url;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      // While checking, just show the app behind it (or a splash, but checking is fast)
      return widget.child;
    }
    
    if (_downloadUrl != null) {
      // Force update screen
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(), // simple dark theme for update screen
        home: UpdateScreen(downloadUrl: _downloadUrl!),
      );
    }

    return widget.child;
  }
}


class UpdateScreen extends StatefulWidget {
  final String downloadUrl;

  const UpdateScreen({super.key, required this.downloadUrl});

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  double _progress = 0.0;
  bool _isDownloading = false;
  String _statusMessage = 'A mandatory update is available.';

  @override
  void initState() {
    super.initState();
    _startUpdate();
  }

  Future<void> _startUpdate() async {
    setState(() {
      _isDownloading = true;
      _statusMessage = 'Downloading update...';
    });

    await UpdateService.downloadAndInstall(
      widget.downloadUrl,
      (progress) {
        setState(() {
          _progress = progress;
        });
      },
    );

    setState(() {
      _isDownloading = false;
      _statusMessage = 'Update downloaded. Please install to continue.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent back button
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.system_update_rounded,
                  size: 80,
                  color: Colors.blueAccent,
                ),
                const SizedBox(height: 24),
                Text(
                  'Update Required',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  _statusMessage,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (_isDownloading) ...[
                  LinearProgressIndicator(
                    value: _progress,
                    minHeight: 12,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${(_progress * 100).toStringAsFixed(1)}%',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ] else ...[
                  ElevatedButton(
                    onPressed: _startUpdate,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Install Update'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
