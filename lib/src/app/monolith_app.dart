import 'dart:async';

import 'package:flutter/material.dart';

import '../features/shell/presentation/music_shell.dart';
import 'state/app_controller.dart';
import 'state/app_scope.dart';
import 'theme/design_tokens.dart';
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

    // Wait until prefs + the first library scan have run so the persisted
    // "seen" flag is accurate, then only prompt on the very first visit.
    await _controller.whenReady;
    if (!mounted || !_controller.shouldShowImportPrompt) {
      return;
    }
    await _controller.markImportPromptSeen();
    if (!mounted) {
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
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Import'),
            ),
          ],
        );
      },
    );

    if (!mounted || shouldImport != true) {
      return;
    }

    // First-visit request: retry=false so iOS shows the system permission
    // dialog. (retry=true skips straight to Settings, which is only useful
    // after a prior denial.)
    await _controller.setAppleMusicImportEnabled(
      true,
      retryPermissionRequest: false,
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
            theme: MonolithTheme.light(
              AccentSwatch.of(_controller.accentPreset),
            ),
            darkTheme: MonolithTheme.dark(
              AccentSwatch.of(_controller.accentPreset),
            ),
            home: const MusicShell(),
            // Tap anywhere outside a focused text field to dismiss the
            // keyboard (no need to drag it down). Translucent so it never
            // swallows taps meant for buttons, lists, or sliders.
            builder: (context, child) => GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: child,
            ),
          );
        },
      ),
    );
  }
}
