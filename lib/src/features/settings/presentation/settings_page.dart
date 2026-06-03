import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/state/app_scope.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/models/music_models.dart';
import '../../../core/widgets/app_icons.dart';
import '../../storage/presentation/storage_page.dart';
import '../contributors.dart';
import '../developer_identity.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static Uri get _githubUri => DeveloperIdentity.githubUri;
  static Uri get _portfolioUri => DeveloperIdentity.portfolioUri;
  static Uri get _instagramUri => DeveloperIdentity.instagramUri;

  static Future<void> _launch(BuildContext context, Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $uri')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      // A hard left→right swipe pops Settings (it slides back off to the
      // right), matching the swipe-between-tabs gesture on the main screens.
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 300) {
          Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: PhosphorIcon(
            PhosphorIcons.caretLeft(),
            size: 22,
            color: scheme.onSurface,
          ),
          tooltip: 'Back',
        ),
      ),
      body: CustomScrollView(
        slivers: [
          // ── Large title ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenInset,
                AppSpacing.md,
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
                onInstagram: () => _launch(context, _instagramUri),
              ),
            ),
          ),

          // ── Contributors (only shown when list is non-empty) ────────
          if (contributors.isNotEmpty) ...[
            _SectionLabel(label: 'Contributors'),
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
                    for (int i = 0; i < contributors.length; i++) ...[
                      if (i > 0) _Divider(),
                      _ContributorRow(entry: contributors[i]),
                    ],
                  ],
                ),
              ),
            ),
          ],

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
                          // No selected check-mark: it competes with each
                          // segment's own icon and squeezes the label onto a
                          // second line (the "m" in "System" dropping down).
                          showSelectedIcon: false,
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
                    switchKey: const Key('normalize-audio-switch'),
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
                AppSpacing.xxl,
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
                    // Leave Settings first (it slides off to the right), then
                    // raise the player so its own open animation plays cleanly
                    // over the shell instead of behind this route.
                    onTap: () {
                      Navigator.of(context).pop();
                      controller.openPlayer();
                    },
                  ),
                  _Divider(),
                  _ActionRow(
                    icon: AppIcons.fileAudio,
                    title: 'Music files',
                    subtitle: 'Browse & share your downloaded tracks',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const StoragePage(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── About ────────────────────────────────────────────────────
          _SectionLabel(label: 'About'),
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
                  _InfoRow(
                    icon: AppIcons.musicNote,
                    title: 'Version',
                    trailing: '1.0.2',
                  ),
                  _Divider(),
                  _InfoRow(
                    icon: AppIcons.compass,
                    title: 'Bundle ID',
                    trailing: DeveloperIdentity.bundleId,
                  ),
                  _Divider(),
                  const _CheckUpdateButton(),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

// ── Developer card ──────────────────────────────────────────────────────────

class _DeveloperCard extends StatelessWidget {
  const _DeveloperCard({
    required this.onGithub,
    required this.onPortfolio,
    required this.onInstagram,
  });
  final VoidCallback onGithub;
  final VoidCallback onPortfolio;
  final VoidCallback onInstagram;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final brightness = Theme.of(context).brightness;
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
        boxShadow: AppElevation.card(brightness),
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
                  DeveloperIdentity.name,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: AppType.title,
                  ),
                ),
                Text(
                  DeveloperIdentity.role,
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
                tooltip: 'Instagram',
                onTap: onInstagram,
                child: const FaIcon(FontAwesomeIcons.instagram, size: 18),
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

// ── Contributor row ──────────────────────────────────────────────────────────

class _ContributorRow extends StatelessWidget {
  const _ContributorRow({required this.entry});
  final ContributorEntry entry;

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
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: AppRadii.all(AppRadii.sm),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
                width: 0.5,
              ),
            ),
            child: Center(
              child: PhosphorIcon(
                AppIcons.person,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: textTheme.bodyLarge?.copyWith(fontWeight: AppType.body),
                ),
                Text(
                  entry.role,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (entry.githubHandle != null)
            _ProfileButton(
              tooltip: 'GitHub',
              onTap: () => launchUrl(
                Uri.parse('https://github.com/${entry.githubHandle}'),
                mode: LaunchMode.externalApplication,
              ),
              child: const FaIcon(FontAwesomeIcons.github, size: 16),
            ),
        ],
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
    final brightness = Theme.of(context).brightness;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
          width: 0.5,
        ),
        boxShadow: AppElevation.card(brightness),
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
    this.switchKey,
  });
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Key? switchKey;

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
            key: switchKey,
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

// ── Info row (non-tappable, shows a trailing value) ──────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.trailing,
  });
  final PhosphorIconData icon;
  final String title;
  final String trailing;

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
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: AppRadii.all(AppRadii.sm),
            ),
            child: Center(
              child: PhosphorIcon(icon, size: 18, color: scheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              title,
              style: textTheme.bodyLarge?.copyWith(fontWeight: AppType.body),
            ),
          ),
          Text(
            trailing,
            style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ── Check for updates button ─────────────────────────────────────────────────

class _CheckUpdateButton extends StatefulWidget {
  const _CheckUpdateButton();

  @override
  State<_CheckUpdateButton> createState() => _CheckUpdateButtonState();
}

class _CheckUpdateButtonState extends State<_CheckUpdateButton> {
  static const _currentVersion = '1.0.2';
  static const _apiUrl =
      'https://api.github.com/repos/naveed-gung/Monolith/releases/latest';
  static const _releasesUrl =
      'https://github.com/naveed-gung/Monolith/releases';

  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final resp = await http
          .get(Uri.parse(_apiUrl))
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final tag =
            (body['tag_name'] as String? ?? '').replaceFirst(RegExp('^v'), '');
        if (_isNewer(tag, _currentVersion)) {
          _showUpdateDialog(tag);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("You're up to date.")),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Check failed (${resp.statusCode}).')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not check for updates.')),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  bool _isNewer(String latest, String current) {
    List<int> parse(String v) =>
        v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final l = parse(latest);
    final c = parse(current);
    for (var i = 0; i < 3; i++) {
      final lv = i < l.length ? l[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }

  void _showUpdateDialog(String newVersion) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New version available'),
        content: Text('Version $newVersion is available on GitHub.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(
                Uri.parse(_releasesUrl),
                mode: LaunchMode.externalApplication,
              );
            },
            child: const Text('Download Now'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: _checking ? null : _check,
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
                child: _checking
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimaryContainer,
                        ),
                      )
                    : PhosphorIcon(
                        AppIcons.refresh,
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
                    'Check for updates',
                    style:
                        textTheme.bodyLarge?.copyWith(fontWeight: AppType.body),
                  ),
                  Text(
                    _checking ? 'Checking…' : 'Tap to check GitHub releases',
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (!_checking)
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
