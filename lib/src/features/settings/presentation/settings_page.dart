import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/state/app_scope.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/models/music_models.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/section_header.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const String _profileImageAsset = 'assets/images/profile.jpg';
  static final Uri _githubUri = Uri.parse('https://github.com/naveed-gung/');
  static final Uri _portfolioUri = Uri.parse('https://naveed-gung.dev/');

  static Future<void> _openExternalLink(
    BuildContext context,
    Uri uri,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open ${uri.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watch(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenInset,
          0,
          AppSpacing.screenInset,
          AppSpacing.xxxl + AppSpacing.xxl,
        ),
        children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Tune the shell, playback behavior, and how the app reacts to imported media.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ── Appearance ──────────────────────────────────────────────────
          GlassPanel(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'Appearance'),
                const SizedBox(height: AppSpacing.md),
                SegmentedButton<ThemePreference>(
                  segments: [
                    ButtonSegment(
                      value: ThemePreference.system,
                      label: const Text('System'),
                      icon: PhosphorIcon(AppIcons.themeSystem, size: 18),
                    ),
                    ButtonSegment(
                      value: ThemePreference.light,
                      label: const Text('Light'),
                      icon: PhosphorIcon(AppIcons.themeLight, size: 18),
                    ),
                    ButtonSegment(
                      value: ThemePreference.dark,
                      label: const Text('Dark'),
                      icon: PhosphorIcon(AppIcons.themeDark, size: 18),
                    ),
                  ],
                  selected: {controller.themePreference},
                  onSelectionChanged: (selection) =>
                      controller.setThemePreference(selection.first),
                ),
                const SizedBox(height: AppSpacing.lg),
                const SectionHeader(title: 'Accent colour'),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: [
                    for (final swatch in AccentSwatch.all)
                      _AccentDot(
                        swatch: swatch,
                        selected:
                            controller.accentPreset == swatch.preset,
                        onTap: () =>
                            controller.setAccentPreset(swatch.preset),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: controller.immersiveCanvas,
                  onChanged: controller.setImmersiveCanvas,
                  title: const Text('Immersive artwork canvas'),
                  subtitle: const Text(
                    'Keep the backdrop reactive to the current record.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Playback ─────────────────────────────────────────────────────
          GlassPanel(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'Playback rules'),
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: controller.downloadsOnWifi,
                  onChanged: controller.setDownloadsOnWifi,
                  title: const Text('Download on Wi-Fi only'),
                  subtitle: const Text(
                    'Protect cellular bandwidth for offline sync.',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: controller.normalizeAudio,
                  onChanged: controller.setNormalizeAudio,
                  title: const Text('Normalize audio'),
                  subtitle: const Text(
                    'Balance playback levels between source masters.',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: controller.smoothTransitions,
                  onChanged: controller.setSmoothTransitions,
                  title: const Text('Smooth transitions'),
                  subtitle: const Text(
                    'Fade between tracks when moving through a queue.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Shortcuts ───────────────────────────────────────────────────
          GlassPanel(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'Workspace shortcuts'),
                const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: PhosphorIcon(AppIcons.compass),
                  title: const Text('Reset search'),
                  subtitle: const Text(
                    'Clear the current search state for a fresh browse.',
                  ),
                  trailing: PhosphorIcon(AppIcons.caretRight),
                  onTap: controller.clearSearchFilters,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: PhosphorIcon(AppIcons.playCircle),
                  title: const Text('Open player cockpit'),
                  subtitle: const Text(
                    'Jump back into the active queue and playback controls.',
                  ),
                  trailing: PhosphorIcon(AppIcons.caretRight),
                  onTap: controller.openPlayer,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Developer card ───────────────────────────────────────────────
          GlassPanel(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'Developer'),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.14),
                        borderRadius: AppRadii.all(AppRadii.sm),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withValues(alpha: 0.18),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        _profileImageAsset,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return PhosphorIcon(
                            AppIcons.person,
                            color: Theme.of(context).colorScheme.primary,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Naveed Gung',
                            style:
                                Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Developer',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'GitHub',
                      onPressed: () =>
                          _openExternalLink(context, _githubUri),
                      icon: const FaIcon(FontAwesomeIcons.github),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    IconButton.filledTonal(
                      tooltip: 'Portfolio',
                      onPressed: () =>
                          _openExternalLink(context, _portfolioUri),
                      icon: PhosphorIcon(AppIcons.globe),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.swatch,
    required this.selected,
    required this.onTap,
  });

  final AccentSwatch swatch;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: swatch.label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.durFast,
          curve: AppMotion.standard,
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: swatch.base,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.transparent,
              width: 2.5,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: swatch.base.withValues(alpha: 0.45),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: selected
              ? Icon(Icons.check_rounded, color: swatch.on, size: 18)
              : null,
        ),
      ),
    );
  }
}
