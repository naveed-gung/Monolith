import 'package:flutter/material.dart';

class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.onMenuPressed,
    required this.onProfilePressed,
    required this.statusLabel,
  });

  final VoidCallback onMenuPressed;
  final VoidCallback onProfilePressed;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Row(
        children: [
          IconButton.filledTonal(
            key: const Key('menu-button'),
            onPressed: onMenuPressed,
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Downloads',
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Monolith', style: textTheme.headlineMedium),
            ),
          ),
          FilledButton.tonalIcon(
            key: const Key('settings-button'),
            onPressed: onProfilePressed,
            icon: const Icon(Icons.tune_rounded),
            label: Text(statusLabel),
          ),
        ],
      ),
    );
  }
}
