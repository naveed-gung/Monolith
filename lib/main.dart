import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'src/app/monolith_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'dev.naveed_gung.monolith.playback',
    androidNotificationChannelName: 'Monolith playback',
    androidNotificationOngoing: true,
  );

  // Configure the platform audio session for music playback BEFORE the first
  // track loads. Without this, iOS leaves the session in its default ambient
  // category: the very first downloaded track would report 00:00 / 00:00 and
  // stay silent until the app was killed and relaunched (the session only got
  // promoted on a later cold start). Configuring it here makes playback work
  // on the first try, every time.
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  runApp(const MonolithApp());
}
