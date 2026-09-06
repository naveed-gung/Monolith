// ignore_for_file: avoid_print
import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
Future<void> main() async {
 final yt = YoutubeExplode();
 try {
  final video = await yt.videos.get('jNQXAC9IVRw').timeout(const Duration(seconds: 25));
  print('Metadata: ${video.title}, ${video.duration}');
  final manifest = await yt.videos.streams.getManifest(video.id, ytClients: [YoutubeApiClient.androidSdkless]).timeout(const Duration(seconds: 25));
  final stream = manifest.audioOnly.where((s) => s.container == StreamContainer.mp4).withHighestBitrate();
  print('AAC stream available: ${stream.size.totalBytes} bytes');
  var bytes = 0;
  await for (final chunk in yt.videos.streams.get(stream).timeout(const Duration(seconds: 25))) { bytes += chunk.length; }
  print('Complete audio download: $bytes bytes');
 } catch (e) { print('Source test failed: $e'); exitCode = 1; }
 finally { yt.close(); }
}
