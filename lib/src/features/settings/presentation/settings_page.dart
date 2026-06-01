import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/state/app_scope.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/models/music_models.dart';
import '../../../core/widgets/app_icons.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static final Uri _githubUri = Uri.parse('https://github.com/naveed-gung/');
  static final Uri _portfolioUri = Uri.parse('https://naveed-gung.dev/');

  static Future<void> _launch(BuildContext context, Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${uri.host}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: CustomScrollView(
        slivers: [
          // ── Large title ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenInset,
                AppSpacing.xl + AppSpacing.xl,
                AppSpacing.screenInset,
                AppSpacing.xxl,
              ),
              child: Text(
                'Settings',
                style: textTheme.displaySmall?.copyWith(
                  fontWeight: AppType.display,
                  letterSpacing: AppType.trackTight,
                ),
              ),
            ),
          ),

          // ── Developer card ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenInset,
                0,
                AppSpacing.screenInset,
                AppSpacing.xxl,
              ),
              child: _DeveloperCard(
                onGithub: () => _launch(context, _githubUri),
                onPortfolio: () => _launch(context, _portfolioUri),
              ),
            ),
          ),

          // ── Appearance ──────────────────────────────────────────────
          _SectionLabel(label: 'Appearance'),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenInset,
                0,
                AppSpacing.screenInset,
                AppSpacing.xxl,
              ),
              child: _SettingsGroup(
                children: [
                  // Theme picker
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Colour scheme',
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: AppType.label,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SegmentedButton<ThemePreference>(
                          segments: [
                            ButtonSegment(
                              value: ThemePreference.system,
                              label: const Text('System'),
                              icon: PhosphorIcon(AppIcons.themeSystem, size: 16),
                            ),
                            ButtonSegment(
                              value: ThemePreference.light,
                              label: const Text('Light'),
                              icon: PhosphorIcon(AppIcons.themeLight, size: 16),
                            ),
                            ButtonSegment(
                              value: ThemePreference.dark,
                              label: const Text('Dark'),
                              icon: PhosphorIcon(AppIcons.themeDark, size: 16),
                            ),
                          ],
                          selected: {controller.themePreference},
                          onSelectionChanged: (s) =>
                              controller.setThemePreference(s.first),
                          style: SegmentedButton.styleFrom(
                            textStyle: textTheme.labelMedium?.copyWith(
                              fontWeight: AppType.label,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _Divider(),
                  // Accent picker
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Accent colour',
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: AppType.label,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: [
                            for (final swatch in AccentSwatch.all) ...[
                              _AccentDot(
                                swatch: swatch,
                                selected:
                                    controller.accentPreset == swatch.preset,
                                onTap: () =>
                                    controller.setAccentPreset(swatch.preset),
                              ),
                              const SizedBox(width: AppSpacing.md),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  _Divider(),
                  _ToggleRow(
                    title: 'Immersive canvas',
                    subtitle: 'Reactive backdrop behind album art',
                    value: controller.immersiveCanvas,
                    onChanged: controller.setImmersiveCanvas,
                  ),
                ],
              ),
            ),
          ),

          // ── Playback ────────────────────────────────────────────────
          _SectionLabel(label: 'Playback'),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenInset,
                0,
                AppSpacing.screenInset,
                AppSpacing.xxl,
              ),
              child: _SettingsGroup(
                children: [
                  _ToggleRow(
                    title: 'Wi-Fi only downloads',
                    subtitle: 'Protect mobile data during sync',
                    value: controller.downloadsOnWifi,
                    onChanged: controller.setDownloadsOnWifi,
                  ),
                  _Divider(),
                  _ToggleRow(
                    title: 'Normalize audio',
                    subtitle: 'Balance levels between tracks',
                    value: controller.normalizeAudio,
                    onChanged: controller.setNormalizeAudio,
                  ),
                  _Divider(),
                  _ToggleRow(
                    title: 'Smooth transitions',
                    subtitle: 'Fade between queue tracks',
                    value: controller.smoothTransitions,
                    onChanged: controller.setSmoothTransitions,
                  ),
                ],
              ),
            ),
          ),

          // ── Shortcuts ───────────────────────────────────────────────
          _SectionLabel(label: 'Quick actions'),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenInset,
                0,
                AppSpacing.screenInset,
                AppSpacing.xxxl + AppSpacing.xxl,
              ),
              child: _SettingsGroup(
                children: [
                  _ActionRow(
                    icon: AppIcons.compass,
                    title: 'Reset search',
                    subtitle: 'Clear filters for a fresh browse',
                    onTap: controller.clearSearchFilters,
                  ),
                  _Divider(),
                  _ActionRow(
                    icon: AppIcons.playCircle,
                    title: 'Open player',
                    subtitle: 'Jump to the active playback controls',
                    onTap: controller.openPlayer,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Developer card ──────────────────────────────────────────────────────────

class _DeveloperCard extends StatelessWidget {
  const _DeveloperCard({required this.onGithub, required this.onPortfolio});
  final VoidCallback onGithub;
  final VoidCallback onPortfolio;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.6),
            scheme.surfaceContainerLow,
          ],
        ),
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          // Profile photo
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: AppRadii.all(AppRadii.md),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/images/profile.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: scheme.primaryContainer,
                child: PhosphorIcon(
                  AppIcons.person,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Naveed Gung',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: AppType.title,
                  ),
                ),
                Text(
                  'Developer',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              _ProfileButton(
                tooltip: 'GitHub',
                onTap: onGithub,
                child: const FaIcon(FontAwesomeIcons.github, size: 18),
              ),
              const SizedBox(width: AppSpacing.sm),
              _ProfileButton(
                tooltip: 'Portfolio',
                onTap: onPortfolio,
                child: PhosphorIcon(AppIcons.globe, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({
    required this.tooltip,
    required this.onTap,
    required this.child,
  });
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.all(AppRadii.sm),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: AppRadii.all(AppRadii.sm),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
          child: Center(
            child: IconTheme(
              data: IconThemeData(color: scheme.onSurface, size: 18),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Settings group (iOS-style rounded card) ──────────────────────────────────

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenInset + AppSpacing.sm,
          0,
          AppSpacing.screenInset,
          AppSpacing.sm,
        ),
        child: Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: AppType.label,
                letterSpacing: AppType.trackWide,
              ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      indent: AppSpacing.lg,
      endIndent: 0,
      color: scheme.outlineVariant.withValues(alpha: 0.4),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.bodyLarge?.copyWith(fontWeight: AppType.body),
                ),
                Text(
                  subtitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final PhosphorIconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: AppRadii.all(AppRadii.sm),
              ),
              child: Center(
                child: PhosphorIcon(
                  icon,
                  size: 18,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.bodyLarge?.copyWith(fontWeight: AppType.body),
                  ),
                  Text(
                    subtitle,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            PhosphorIcon(
              AppIcons.caretRight,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Accent swatch dot ────────────────────────────────────────────────────────

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
          width: 34,
          height: 34,
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
                      color: swatch.base.withValues(alpha: 0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: selected
              ? Center(
                  child: Icon(Icons.check_rounded, color: swatch.on, size: 16),
                )
              : null,
        ),
      ),
    );
  }
}
