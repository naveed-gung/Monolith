import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/state/app_scope.dart';
import '../../../core/models/music_models.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/section_header.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const String _profileImageUrl =
      'https://instagram.fbey14-1.fna.fbcdn.net/v/t51.82787-19/686301220_18456986572128279_8286432443934980707_n.jpg?stp=dst-jpg_s150x150_tt6&efg=eyJ2ZW5jb2RlX3RhZyI6InByb2ZpbGVfcGljLmRqYW5nby44MjAuYzIifQ&_nc_ht=instagram.fbey14-1.fna.fbcdn.net&_nc_cat=103&_nc_oc=Q6cZ2gHtyfTH7K3Lc9pGTvFyu_nZ5WN6qJmOg2hxtpx2Gac754AFbI9by2GpF5crOzv9JVU&_nc_ohc=uethdjYg3_wQ7kNvwGkoIsS&_nc_gid=heHnhb94kUj3arP70RiR5g&edm=AOQ1c0wBAAAA&ccb=7-5&oh=00_Af_BszPRvnsZQGdsndvsId00ph1pC9tEP7pki8Bjd1dIbg&oe=6A232DF5&_nc_sid=8b3546';
  static final Uri _githubUri = Uri.parse('https://github.com/naveed-gung/');
  static final Uri _portfolioUri = Uri.parse('https://naveed-gung.dev/');

  static Future<void> _openExternalLink(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

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
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 180),
        children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Tune the shell, playback behavior, and how the app reacts to imported media.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          GlassPanel(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'Appearance'),
                const SizedBox(height: 14),
                SegmentedButton<ThemePreference>(
                  segments: const [
                    ButtonSegment(
                      value: ThemePreference.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto_rounded),
                    ),
                    ButtonSegment(
                      value: ThemePreference.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_rounded),
                    ),
                    ButtonSegment(
                      value: ThemePreference.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_rounded),
                    ),
                  ],
                  selected: {controller.themePreference},
                  onSelectionChanged: (selection) {
                    controller.setThemePreference(selection.first);
                  },
                ),
                const SizedBox(height: 18),
                SwitchListTile.adaptive(
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
          const SizedBox(height: 18),
          GlassPanel(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'Playback rules'),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: controller.downloadsOnWifi,
                  onChanged: controller.setDownloadsOnWifi,
                  title: const Text('Download on Wi-Fi only'),
                  subtitle: const Text(
                    'Protect cellular bandwidth for offline sync.',
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: controller.normalizeAudio,
                  onChanged: controller.setNormalizeAudio,
                  title: const Text('Normalize audio'),
                  subtitle: const Text(
                    'Balance playback levels between source masters.',
                  ),
                ),
                SwitchListTile.adaptive(
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
          const SizedBox(height: 18),
          GlassPanel(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'Workspace shortcuts'),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.travel_explore_rounded),
                  title: const Text('Reset search'),
                  subtitle: const Text(
                    'Clear the current search state for a fresh browse.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: controller.clearSearchFilters,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.play_circle_outline_rounded),
                  title: const Text('Open player cockpit'),
                  subtitle: const Text(
                    'Jump back into the active queue and playback controls.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: controller.openPlayer,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          GlassPanel(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'Developer'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.18),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.network(
                        _profileImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.person_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Naveed Gung',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Developer',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'GitHub',
                      onPressed: () => _openExternalLink(context, _githubUri),
                      icon: const FaIcon(FontAwesomeIcons.github),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                      tooltip: 'Portfolio',
                      onPressed: () =>
                          _openExternalLink(context, _portfolioUri),
                      icon: const Icon(Icons.language_rounded),
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
