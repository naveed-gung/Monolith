import 'dart:async';

import 'package:flutter/material.dart';

import '../features/shell/presentation/music_shell.dart';
import 'state/app_controller.dart';
import 'state/app_scope.dart';
import 'theme/monolith_theme.dart';

class MonolithApp extends StatefulWidget {
  const MonolithApp({super.key, this.controller});

  final MonolithController? controller;

  @override
  State<MonolithApp> createState() => _MonolithAppState();
}

class _MonolithAppState extends State<MonolithApp> {
  late final MonolithController _controller;
  late final bool _ownsController;
  bool _didQueueStartupPrompt = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? MonolithController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didQueueStartupPrompt) {
      return;
    }

    _didQueueStartupPrompt = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybePromptForAppleMusicImport());
    });
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _maybePromptForAppleMusicImport() async {
    if (!mounted || !_controller.supportsAppleMusicImportPrompt) {
      return;
    }

    final shouldImport = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Import from Apple Music?'),
          content: const Text(
            'On iOS, Monolith can pull in the songs already available in your Apple Music library and downloaded music collection. Import them now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Import library'),
            ),
          ],
        );
      },
    );

    if (!mounted || shouldImport != true) {
      return;
    }

    await _controller.setAppleMusicImportEnabled(
      true,
      retryPermissionRequest: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: _controller,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return MaterialApp(
            title: 'Monolith',
            debugShowCheckedModeBanner: false,
            themeMode: _controller.themeMode,
            theme: MonolithTheme.light,
            darkTheme: MonolithTheme.dark,
            home: const MusicShell(),
          );
        },
      ),
    );
  }
}
