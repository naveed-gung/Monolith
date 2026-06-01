import 'package:flutter/material.dart';

import '../../../app/state/app_scope.dart';
import '../../../core/models/music_models.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/section_header.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

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
        ],
      ),
    );
  }
}
