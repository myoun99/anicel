import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// F-132 — a rail row's label is pressed without ink, on every rail.
///
/// 유저 2026-09-14: 「x시트 레이어라벨만 클릭했을때 흰색으로 채워지는
/// 애니메이션 없는데, 이거 맘에듬. 일단 그부분 타임라인이랑 스토리보드패널이랑
/// 법 하나로 통일시키고, 애니메이션 없도록 하도록」.
///
/// The labels press through an [InkWell] for its place in the gesture arena;
/// what the user saw was that InkWell's splash and highlight filling the row.
/// The timeline and the x-sheet share one row widget, so the timeline's labels
/// and the storyboard's are read here.
void main() {
  List<InkWell> labelInkWells(
    WidgetTester tester,
    bool Function(String key) isLabel,
  ) => tester
      .widgetList<InkWell>(
        find.byWidgetPredicate(
          (widget) =>
              widget is InkWell &&
              widget.key is ValueKey<String> &&
              isLabel((widget.key! as ValueKey<String>).value),
        ),
      )
      .toList();

  void expectInkless(List<InkWell> labels) {
    expect(labels, isNotEmpty, reason: 'fixture: the rail draws labels');
    for (final label in labels) {
      expect(
        label.splashFactory,
        NoSplash.splashFactory,
        reason: '${label.key}: no fill spreads from the press',
      );
      expect(
        label.highlightColor,
        Colors.transparent,
        reason: '${label.key}: no highlight while held',
      );
    }
  }

  testWidgets('the timeline\'s layer labels press without ink', (
    tester,
  ) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineTabHost(
            session: session,
            orientation: TimelineOrientation.horizontal,
            onOrientationChanged: (_) {},
            pixelsPerFrame: 24,
            onPixelsPerFrameChanged: (_) {},
            showSeconds: false,
            onShowSecondsChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expectInkless(
      labelInkWells(tester, (key) => key.startsWith('timeline-layer-row-')),
    );

    // Drain the prerender scheduler's debounced warming.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('the storyboard\'s track and S-row labels press without ink', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => StoryboardTabHost(
              session: session,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnailFor: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expectInkless(
      labelInkWells(
        tester,
        (key) =>
            key.startsWith('storyboard-track-select-') ||
            key.startsWith('storyboard-se-label-'),
      ),
    );
  });
}
