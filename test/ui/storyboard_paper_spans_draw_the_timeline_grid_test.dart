import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';

/// F-92 — the storyboard's paper blocks draw the timeline's frame grid.
///
/// 유저 2026-09-12: 「스토리보드패널의 프레임셀 그리드, 타임라인패널이랑 다름.
/// 타임라인 패널은 줌 축소해서 1f그리드가 생략되는 구간 오면 프레임블록의
/// 그리드도 결과적으로 그거랑 맞춰져있는데 스토리보드패널은 안맞춰지고 줌
/// 축소해도 1f마다 블록에 세로선이있음. 타임라인이랑 다른 법 절대로 두지말고
/// 관련 로직 싹 다 통일」.
///
/// Measured on the real storyboard: an S row's sound block, its paper painted
/// into a recording canvas, against what the timeline's grid law keeps over
/// the same frames at the same zoom.
void main() {
  const soundStart = 3;
  const soundLength = 12;

  /// The default project with one sound on the first S row, from global frame
  /// [soundStart], and the storyboard at [pixelsPerFrame]. Returns the key of
  /// that sound's paper.
  Future<(EditorSessionManager, String)> storyboardWithASound(
    WidgetTester tester, {
    required double pixelsPerFrame,
  }) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final seId = session.activeTrack.seLayers.first.id;
    session.selectLayer(seId);
    session.selectFrameIndex(soundStart);
    session.seEntries.createSeEntryAtCurrentFrame(
      name: 'a',
      lengthFrames: soundLength,
    );
    expect(
      session.activeTrack.seLayers.first.timeline[soundStart]?.length,
      soundLength,
      reason: 'fixture: the sound stands where the test reads it',
    );
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => StoryboardTabHost(
              session: session,
              pixelsPerFrame: pixelsPerFrame,
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
    return (session, 'storyboard-se-paper-${seId.value}-$soundStart');
  }

  /// The lines the paper under [key] draws.
  List<({double along, Color color})> linesOf(
    WidgetTester tester,
    String key,
  ) {
    final span = find.byKey(ValueKey<String>(key));
    expect(span, findsOneWidget);
    final paint = tester.widget<CustomPaint>(
      find.descendant(of: span, matching: find.byType(CustomPaint)).first,
    );
    final spy = _LineSpy();
    paint.painter!.paint(spy, tester.getSize(span));
    return spy.lines;
  }

  /// The boundaries inside the sound that the timeline's cells draw at
  /// [pixelsPerFrame], as positions along the span.
  List<double> positionsTheLawKeeps(double pixelsPerFrame) => [
    for (var offset = 1; offset < soundLength; offset += 1)
      if (timelineFrameBoundaryLineInk(
            frameIndex: soundStart + offset,
            frameCellExtent: pixelsPerFrame,
            framesPerSecond: 24,
            colorScheme: const ColorScheme.light(),
          ) !=
          null)
        timelineFrameBoundaryLinePosition(offset, pixelsPerFrame),
  ];

  testWidgets('zoomed out, a sound block keeps only the lines the timeline '
      'keeps, where the timeline puts them', (tester) async {
    final (_, key) = await storyboardWithASound(tester, pixelsPerFrame: 2.4);
    final kept = positionsTheLawKeeps(2.4);
    expect(
      kept.length,
      lessThan(soundLength - 1),
      reason: 'fixture: at 10% the law thins the grid',
    );

    expect(linesOf(tester, key).map((line) => line.along), kept);
  });

  testWidgets('the six-frame line wears the law\'s ink over the block\'s '
      'paper', (tester) async {
    final (session, key) = await storyboardWithASound(
      tester,
      pixelsPerFrame: 8,
    );
    final span = tester.element(find.byKey(ValueKey<String>(key)));
    final law = span.findAncestorWidgetOfExactType<TimelineGridLaw>()!;
    final paper = layerMarkColor(session.activeTrack.seLayers.first.mark);
    final six = timelineFrameBoundaryLinePosition(6 - soundStart, 8);

    final line = linesOf(tester, key).firstWhere((line) => line.along == six);

    // ⚠️Read back through a Paint, as the spy reads the line: a Paint keeps
    // its colour at float32, so the law's double-precision answer and the
    // same colour after that trip differ past the fifth decimal.
    expect(
      line.color,
      (Paint()
            ..color = timelineGridLineInkOnGround(
              timelineGridSixLineInk(Theme.of(span).colorScheme),
              timelineGridGroundOver(under: law.ground, painted: paper)!,
            ))
          .color,
    );
  });

  testWidgets('zoomed in, it draws every boundary, as the timeline does', (
    tester,
  ) async {
    final (_, key) = await storyboardWithASound(tester, pixelsPerFrame: 24);

    expect(
      linesOf(tester, key).map((line) => line.along),
      [
        for (var offset = 1; offset < soundLength; offset += 1)
          timelineFrameBoundaryLinePosition(offset, 24),
      ],
    );
  });
}

class _LineSpy implements Canvas {
  final lines = <({double along, Color color})>[];

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) =>
      lines.add((along: p1.dx, color: paint.color));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
