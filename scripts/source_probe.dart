// ignore_for_file: avoid_print
import 'dart:io';
import '../lib/src/core/services/audio_stream_transfer.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main(List<String> args) async {
  final yt = YoutubeExplode();
  try {
    final video = await yt.videos
        .get(args.isEmpty ? 'jNQXAC9IVRw' : args.first)
        .timeout(const Duration(seconds: 25));
    print('Metadata: ${video.title}, ${video.duration}');
    final client = YoutubeApiClient.androidSdkless;
    final manifest = await yt.videos.streams
        .getManifest(video.id, ytClients: [client])
        .timeout(const Duration(seconds: 25));
    final streams = manifest.audioOnly
        .where((s) => s.container == StreamContainer.mp4)
        .toList();
    final stream =
        streams.where((s) => s.tag == 140).firstOrNull ??
        streams.withHighestBitrate();
    print(
      'AAC stream available: ${stream.size.totalBytes} bytes; itag ${stream.tag}, client ${stream.url.queryParameters['c']}',
    );
    final file = File('build/source-probe-audio.part');
    try {
      await AudioStreamTransfer().download(
        url: stream.url,
        headers: {
          if (client.payload['context']['client']['userAgent']
              case final String agent)
            'User-Agent': agent,
        },
        size: stream.size.totalBytes,
        destination: file,
        onProgress: (_) {},
      );
      print('Complete bounded audio download: ${await file.length()} bytes');
    } finally {
      if (await file.exists()) await file.delete();
    }
  } catch (e) {
    print('Source test failed: $e');
    exitCode = 1;
  } finally {
    yt.close();
  }
}
