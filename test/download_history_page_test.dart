import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monolith/src/app/state/app_controller.dart';
import 'package:monolith/src/app/state/app_scope.dart';
import 'package:monolith/src/core/models/music_models.dart';
import 'package:monolith/src/features/settings/presentation/download_history_page.dart';

class _HistoryController extends ChangeNotifier implements MonolithController {
  @override
  List<DownloadHistoryEntry> downloadHistory = [
    const DownloadHistoryEntry(
      title: 'Saved song',
      url: 'https://youtu.be/jNQXAC9IVRw',
    ),
  ];
  Track? existing = const Track(
    id: 'saved',
    title: 'Saved song',
    artist: '',
    album: '',
    genre: '',
    duration: Duration.zero,
    colors: [],
    blurb: '',
    source: TrackSource.downloaded,
  );
  final replacements = <bool>[];
  @override
  Future<Track?> downloadedTrackForUrl(String url) async => existing;
  @override
  Future<void> redownloadHistoryEntry(
    DownloadHistoryEntry entry, {
    bool replaceExisting = false,
  }) async {
    replacements.add(replaceExisting);
  }

  @override
  Future<void> clearDownloadHistory() async {
    downloadHistory = [];
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'history confirms replacement, downloads missing songs, and clears only history',
    (tester) async {
      final controller = _HistoryController();
      await tester.pumpWidget(
        AppScope(
          controller: controller,
          child: const MaterialApp(home: DownloadHistoryPage()),
        ),
      );
      await tester.tap(find.text('Saved song'));
      await tester.pumpAndSettle();
      expect(find.text('You already have this song'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.replacements, isEmpty);
      await tester.tap(find.text('Saved song'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get anyway'));
      await tester.pumpAndSettle();
      expect(controller.replacements, [true]);
      controller.existing = null;
      await tester.tap(find.text('Saved song'));
      await tester.pumpAndSettle();
      expect(controller.replacements, [true, false]);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Saved songs stay'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Clear').last);
      await tester.pumpAndSettle();
      expect(controller.downloadHistory, isEmpty);
      expect(
        find.text('Your download links will appear here.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
