import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/envelope/cut_envelope_presets.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/ui/dialogs/work_settings_window.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// 작품 설정 (유저 09-25, project-settings-window): the work's title and
/// episode, and its staff by the colour labels — two folds, the staff
/// folded until opened. The staff is the conte's alone (유저 2026-10-08,
/// F-291-Q1: 「스태프는 콘티만 남겨둠. 나머진 삭제. 나머진 컷마다
/// 스태프설정」).
void main() {
  const conte = LayerMark(process: LayerProcess.conte);
  const conteDirector = LayerMark(
    process: LayerProcess.conte,
    revise: LayerRevise.director,
  );

  Future<void> openWindow(
    WidgetTester tester,
    TimesheetInfo initial,
    void Function(TimesheetInfo? result) onResult, {
    List<MediaAsset> pictures = const [],
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                onResult(
                  await showDialog<TimesheetInfo>(
                    context: context,
                    builder: (_) => WorkSettingsWindow(
                      initialInfo: initial,
                      projectName: 'Untitled 3',
                      pictures: pictures,
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder rowOf(LayerMark mark) =>
      find.byKey(ValueKey<String>('work-settings-staff-${mark.keySlug}'));

  /// Taps the header of the fold keyed [key].
  Future<void> toggle(WidgetTester tester, String key) async {
    final header = find
        .descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byType(InkWell),
        )
        .first;
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    final button = find.byKey(
      const ValueKey<String>('work-settings-save-button'),
    );
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('it opens on the work, the staff folded — 「기본값은 스태프설정만 '
      '접기」', (tester) async {
    await openWindow(tester, TimesheetInfo.empty, (_) {});

    expect(
      find.byKey(const ValueKey<String>('work-settings-title-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('work-settings-episode-field')),
      findsOneWidget,
    );
    expect(rowOf(conte), findsNothing, reason: 'the staff is folded');
    expect(
      find.text(AppText.strings.workSettingsStaff),
      findsOneWidget,
      reason: 'a fold holding no names yet says only its name',
    );
  });

  testWidgets('🎯the staff is the conte\'s: its worker and the corrections it '
      'references — every other stage is the cut\'s, and 用紙 nobody\'s', (
    tester,
  ) async {
    await openWindow(tester, TimesheetInfo.empty, (_) {});
    await toggle(tester, 'work-settings-staff');

    for (final mark in everyLayerMark()) {
      final process = mark.process;
      if (process == null) {
        continue;
      }
      expect(
        rowOf(mark),
        process == LayerProcess.conte ? findsOneWidget : findsNothing,
        reason: mark.keySlug,
      );
      if (process != LayerProcess.conte) {
        expect(
          find.byKey(
            ValueKey<String>('work-settings-process-${process.jsonValue}'),
          ),
          findsNothing,
          reason: 'and no fold of its own',
        );
      }
    }
  });

  testWidgets('the conte\'s fold folds on its own', (tester) async {
    await openWindow(tester, TimesheetInfo.empty, (_) {});
    await toggle(tester, 'work-settings-staff');

    await toggle(tester, 'work-settings-process-conte');

    expect(rowOf(conte), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('work-settings-process-conte')),
      findsOneWidget,
      reason: 'folded, not gone',
    );
  });

  testWidgets('what is typed is saved under the labels, a stage and its '
      'correction apart; a row left blank writes nothing', (tester) async {
    TimesheetInfo? saved;
    await openWindow(tester, TimesheetInfo.empty, (r) => saved = r);
    await tester.enterText(
      find.byKey(const ValueKey<String>('work-settings-title-field')),
      'YOASOBI',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('work-settings-episode-field')),
      '#3',
    );
    await toggle(tester, 'work-settings-staff');
    await tester.ensureVisible(rowOf(conte));
    await tester.enterText(rowOf(conte), '大川');
    await tester.ensureVisible(rowOf(conteDirector));
    await tester.enterText(rowOf(conteDirector), '清');

    await save(tester);

    expect(saved!.title, 'YOASOBI');
    expect(saved!.episode, '#3');
    expect(saved!.staff, {
      conte.keySlug: '大川',
      conteDirector.keySlug: '清',
    });
  });

  testWidgets('the empty title shows the project\'s name — what the paper '
      'prints for it', (tester) async {
    await openWindow(tester, TimesheetInfo.empty, (_) {});

    final title = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('work-settings-title-field')),
    );
    expect(title.decoration?.hintText, 'Untitled 3');
  });

  testWidgets('the work\'s pictures are picked from the pool\'s images — the '
      'logo, the cover, or none — and named as the pool names them', (
    tester,
  ) async {
    const logo = 'C:/pool/studio.png';
    const cover = 'C:/pool/key.png';
    final before = WorkPicture.cover.withPath(TimesheetInfo.empty, cover);
    TimesheetInfo? after;
    await openWindow(
      tester,
      before,
      (r) => after = r,
      pictures: [
        MediaAsset(path: logo, name: 'Studio', kind: MediaAssetKind.image),
        MediaAsset(path: cover, name: 'Key visual', kind: MediaAssetKind.image),
      ],
    );
    String label(WorkPicture picture) => tester
        .widget<PanelFlyoutButton>(
          find.byKey(ValueKey<String>('work-settings-picture-${picture.name}')),
        )
        .label;
    Future<void> pick(WorkPicture picture, String choice) async {
      final button = 'work-settings-picture-${picture.name}';
      await tester.ensureVisible(find.byKey(ValueKey<String>(button)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey<String>(button)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey<String>('$button-$choice')));
      await tester.pumpAndSettle();
    }

    expect(label(WorkPicture.logo), AppText.strings.commonNone);
    expect(label(WorkPicture.cover), 'Key visual');

    await pick(WorkPicture.logo, logo);
    await pick(WorkPicture.cover, 'none');
    expect(label(WorkPicture.logo), 'Studio');
    expect(label(WorkPicture.cover), AppText.strings.commonNone);
    await save(tester);

    expect(after?.logoAssetPath, logo);
    expect(after?.coverImagePath, isNull);
  });

  testWidgets('🚨saving does not reset what this window does not show', (
    tester,
  ) async {
    final before = const TimesheetInfo(
      title: 'T',
      hiddenFields: {TimesheetHeaderField.scene},
      exposureBarThreshold: 4,
      seEmptyFill: false,
      logoAssetPath: 'logo.png',
      coverImagePath: 'cover.png',
      envelopeFormId: CutEnvelopePresets.digitalId,
    ).withStaffName(const LayerMark(process: LayerProcess.conte), '콘티');
    TimesheetInfo? after;
    await openWindow(tester, before, (r) => after = r);

    await save(tester);

    expect(after, before);
  });
}
