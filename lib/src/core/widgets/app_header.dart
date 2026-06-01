import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/theme/design_tokens.dart';
import 'app_icons.dart';

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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenInset,
        AppSpacing.lg,
        AppSpacing.screenInset,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          IconButton.filledTonal(
            key: const Key('menu-button'),
            onPressed: onMenuPressed,
            icon: PhosphorIcon(AppIcons.downloadFill, size: 20),
            tooltip: 'Downloads',
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Monolith',
                style: textTheme.headlineMedium,
              ),
            ),
          ),
          FilledButton.tonalIcon(
            key: const Key('settings-button'),
            onPressed: onProfilePressed,
            icon: PhosphorIcon(AppIcons.settings, size: 18),
            label: Text(statusLabel),
            style: FilledButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
              textStyle: textTheme.labelMedium?.copyWith(
                fontWeight: AppType.label,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
