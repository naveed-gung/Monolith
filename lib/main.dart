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
  runApp(const MonolithApp());
}
