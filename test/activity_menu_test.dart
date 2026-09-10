import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monolith/data/platform_channels/media_import_channel.dart';
import 'package:monolith/src/app/state/app_controller.dart';
import 'package:monolith/src/app/state/app_scope.dart';
import 'package:monolith/src/core/models/music_models.dart';
import 'package:monolith/src/core/services/app_update_service.dart';
import 'package:monolith/src/features/settings/presentation/update_panel.dart';
import 'package:monolith/src/shared/widgets/app_download_indicator.dart';

class _Controller extends ChangeNotifier implements MonolithController {
  @override
  List<DownloadTaskInfo> downloadTasks = [
    for (final id in ['First', 'Second'])
      DownloadTaskInfo(
        processId: id,
        url: '',
        title: '$id song',
        fileName: id,
        status: DownloadTaskStatus.downloading,
        progress: .2,
        totalBytes: 8000,
      ),
  ];
  @override
  bool isImportingAudio = true;
  @override
  bool get isCancellingImport => false;
  @override
  bool get canCancelImport => true;
  @override
  String? get lastImportSummary => null;
  @override
  List<ImportedItemResult> get importFailures => [];
  @override
  double? get importProgress => .3;
  @override
  String? get importStatus => '3 of 10 · Current song';
  final stopped = <String>[];
  @override
  Future<bool> cancelDownload(String id) async {
    stopped.add(id);
    downloadTasks = downloadTasks.where((t) => t.processId != id).toList();
    notifyListeners();
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'activity menu shows concurrent jobs and stops only the selected one',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 900);
      addTearDown(tester.view.reset);
      final controller = _Controller();
      final updates = AppUpdateService(ios: true);
      await tester.pumpWidget(
        AppScope(
          controller: controller,
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  const SizedBox(height: 120),
                  AppDownloadIndicator(updateService: updates),
                ],
              ),
            ),
          ),
        ),
      );
      final carrier = find.byKey(const Key('activity-carrier'));
      expect(tester.getSize(carrier).height, 44);
      await tester.tap(find.byKey(const Key('activity-menu-button')));
      await tester.pump(const Duration(milliseconds: 300));
      final expandedDetails = tester.getRect(
        find.byKey(const Key('activity-details')),
      );
      expect(
        expandedDetails.top - 8 - tester.getRect(carrier).bottom,
        greaterThanOrEqualTo(12),
      );
      expect(expandedDetails.right + 8, lessThanOrEqualTo(304));
      await tester.tap(find.byKey(const Key('activity-menu-button')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 90));
      final midway = tester.getSize(carrier);
      expect(midway.height, 44);
      expect(midway.width, inInclusiveRange(44, 260));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getSize(carrier), const Size(44, 44));
      await tester.tap(find.byKey(const Key('activity-menu-button')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('First song'), findsOneWidget);
      expect(find.text('Second song'), findsOneWidget);
      expect(find.text('3 of 10 · Current song'), findsOneWidget);
      final details = tester.getRect(find.byKey(const Key('activity-details')));
      final button = tester.getRect(carrier);
      expect(details.top - 8 - button.bottom, greaterThanOrEqualTo(12));
      expect(details.left - 8, greaterThanOrEqualTo(16));
      expect(details.right + 8, lessThanOrEqualTo(304));
      await tester.tap(find.byKey(const Key('stop-First')));
      await tester.pump();
      expect(controller.stopped, ['First']);
      expect(
        tester.getSize(carrier),
        const Size(44, 44),
        reason: 'Finishing one concurrent job must not replay the pill.',
      );
      expect(find.text('Second song'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      updates.dispose();
    },
  );

  testWidgets('switching screens does not replay the activity announcement', (
    tester,
  ) async {
    final controller = _Controller();
    final updates = AppUpdateService(ios: true);
    Widget screen(String name) => AppScope(
      controller: controller,
      child: MaterialApp(
        home: Scaffold(
          body: AppDownloadIndicator(
            key: ValueKey(name),
            updateService: updates,
          ),
        ),
      ),
    );
    final carrier = find.byKey(const Key('activity-carrier'));
    await tester.pumpWidget(screen('library'));
    expect(tester.getSize(carrier).width, greaterThan(44));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getSize(carrier).width, 44);
    await tester.pumpWidget(screen('downloads'));
    expect(tester.getSize(carrier).width, 44);
    await tester.pumpWidget(screen('library-again'));
    expect(tester.getSize(carrier).width, 44);

    // Empty activity must reset the batch so a genuinely new job can announce.
    controller.isImportingAudio = false;
    controller.downloadTasks = [];
    controller.notifyListeners();
    await tester.pump();
    expect(carrier, findsNothing);
    controller.isImportingAudio = true;
    controller.notifyListeners();
    await tester.pump();
    expect(tester.getSize(carrier).width, greaterThan(44));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    updates.dispose();
  });

  testWidgets(
    'local IPA action shares the existing file and remains available afterwards',
    (tester) async {
      final file = File('${Directory.systemTemp.path}/monolith-share-test.ipa');
      await tester.runAsync(() => file.writeAsBytes([0x50, 0x4b, 3, 4]));
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });
      final service = AppUpdateService(ios: true)..downloaded = file;
      final calls = <MethodCall>[];
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return 'dev.hegenberg.TrollStore';
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: UpdatePanel(service: service)),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Open downloaded IPA…'));
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump();
      expect(calls.single.method, 'shareFiles');
      expect((calls.single.arguments as Map)['paths'], [file.path]);
      expect(service.isDownloading, isFalse);
      expect(find.text('Open downloaded IPA…'), findsOneWidget);
      expect(find.text('Update installed'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    },
  );
}
