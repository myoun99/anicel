import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/canvas/flip_hud_controller.dart' show FlipHudAxis;
import 'package:anicel/src/ui/canvas/flip_hud_model.dart';
import 'package:anicel/src/ui/canvas/flip_hud_overlay.dart';
import 'package:anicel/src/ui/canvas/guide_overlay.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_painter.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/text/app_face.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/dialogue_fit_text.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';

import '../../helpers/app_faces.dart';
import '../timeline/timeline_row_chrome_probe.dart';
import '../timeline/timeline_ruler_probe.dart';

/// 🚨「앱은 한 글꼴」(유저 2026-08-28), for what a PAINTER writes. A painter
/// that sets its type from scratch names no face and writes in the OS's —
/// the rulers, the run glyphs and the guides' names did, beside names in
/// the app's. These mount the real app and ask each painter the face it
/// was handed where it stands; how each paints in it is pinned beside the
/// painter.
void main() {
  test('the face is the family and the fallback, and nothing else', () {
    final face = appFaceOf(
      const TextStyle(
        fontFamily: 'Face',
        fontFamilyFallback: ['Fallback'],
        fontSize: 30,
        height: 3,
        fontWeight: FontWeight.w900,
        color: Color(0xFFFF0000),
        letterSpacing: 4,
      ),
    );
    expect(
      face,
      const TextStyle(fontFamily: 'Face', fontFamilyFallback: ['Fallback']),
    );
  });

  testWidgets('the ruler, the run glyphs and the guides are handed the '
      'app\'s face where they stand', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(initialProject: _project()),
      ),
    );
    await tester.pumpAndSettle();

    final guides = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is GuideOverlayPainter,
    );
    final handed = <String, (TextStyle, Finder)>{
      'ruler': (
        timelineRulerPainter(tester).scale.face,
        timelineRulerPaintFinder(),
      ),
      'run glyphs': (
        timelineRowChromePainter(tester, 'face-cel')!.face,
        timelineRowChromeFinder('face-cel'),
      ),
      'guides': (
        (tester.widget<CustomPaint>(guides).painter! as GuideOverlayPainter)
            .face,
        guides,
      ),
    };
    for (final MapEntry(key: painter, value: (face, at)) in handed.entries) {
      final ambient = DefaultTextStyle.of(tester.element(at)).style;
      expect(
        ambient.fontFamily,
        isNotNull,
        reason: 'the premise: the theme names the app\'s face',
      );
      expect(face, appFaceOf(ambient), reason: painter);
    }
  });

  testWidgets('the dialogue is spread in the app\'s face', (tester) async {
    await loadTheAppFaces();
    const face = TextStyle(fontFamily: 'BIZ UDPGothic');
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: face,
          child: Center(
            child: SizedBox(
              width: 120,
              height: 28,
              child: DialogueFitText(
                text: 'ABC',
                axis: Axis.horizontal,
                color: Color(0xFF000000),
              ),
            ),
          ),
        ),
      ),
    );
    final painted = _PaintedWidths();
    tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(DialogueFitText),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!
        .paint(painted, const Size(120, 28));
    expect(painted.widths, [
      for (final glyph in ['A', 'B', 'C'])
        closeTo(_widthIn(face, glyph, 12, FontWeight.w600), 0.5),
    ]);
    expect(
      _widthIn(face, 'A', 12, FontWeight.w600),
      isNot(
        closeTo(_widthIn(const TextStyle(), 'A', 12, FontWeight.w600), 0.5),
      ),
      reason: 'the premise: the two faces set a glyph at different widths',
    );
  });

  testWidgets('the flip window\'s rail names its rows in the app\'s face', (
    tester,
  ) async {
    await loadTheAppFaces();
    const face = TextStyle(fontFamily: 'BIZ UDPGothic');
    const painter = FlipHudPainter(
      snapshot: FlipHudSnapshot(
        rows: [
          FlipHudRow(
            name: 'Rail',
            kind: LayerKind.animation,
            runs: [FlipHudRun(startIndex: 0, length: 1, label: '1')],
          ),
        ],
        rowIndex: 0,
        frameIndex: 0,
        frameCount: 8,
      ),
      axis: FlipHudAxis.frame,
      frameStep: true,
      colorScheme: ColorScheme.dark(),
      baseTextStyle: face,
    );
    final painted = _PaintedWidths();
    painter.paint(painted, FlipHudMetrics.sizeFor(FlipHudAxis.frame));
    final name = _widthIn(face, 'Rail', 11.5, FontWeight.w600);
    expect(
      name,
      isNot(
        closeTo(
          _widthIn(const TextStyle(), 'Rail', 11.5, FontWeight.w600),
          0.5,
        ),
      ),
      reason: 'the premise: the two faces set the name at different widths',
    );
    expect(painted.widths, contains(closeTo(name, 0.01)));
  });

  testWidgets('the sheet and the envelope are handed the app\'s face where '
      'they stand (documents-in-which-face-Q1)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(initialProject: _project()),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> open(String tabId) async {
      tester
          .widgetList<EditorPanelTabs>(find.byType(EditorPanelTabs))
          .firstWhere((host) => host.tabs.any((tab) => tab.id == tabId))
          .onTabSelected(tabId);
      await tester.pumpAndSettle();
    }

    void expectHanded(String key, TextStyle Function(CustomPainter) faceOf) {
      final at = find.byKey(ValueKey<String>(key));
      final ambient = DefaultTextStyle.of(tester.element(at)).style;
      expect(
        ambient.fontFamily,
        isNotNull,
        reason: 'the premise: the theme names the app\'s face',
      );
      expect(
        faceOf(tester.widget<CustomPaint>(at).painter!),
        appFaceOf(ambient),
        reason: key,
      );
    }

    await open(EditorWorkspace.timesheetTabId);
    expectHanded(
      'timesheet-form-paint',
      (painter) => (painter as TimesheetDocumentPainter).face,
    );
    expectHanded(
      'timesheet-content-paint',
      (painter) => (painter as TimesheetDocumentPainter).face,
    );
    await open(EditorWorkspace.envelopeTabId);
    expectHanded(
      'envelope-content-paint',
      (painter) => (painter as CutEnvelopePainter).face,
    );
  });
}

double _widthIn(
  TextStyle face,
  String text,
  double size,
  FontWeight weight,
) => (TextPainter(
  text: TextSpan(
    text: text,
    style: face.copyWith(fontSize: size, fontWeight: weight),
  ),
  textDirection: TextDirection.ltr,
)..layout()).maxIntrinsicWidth;

/// The natural width of every paragraph painted, in painting order.
class _PaintedWidths implements Canvas {
  final widths = <double>[];

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) =>
      widths.add(paragraph.maxIntrinsicWidth);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Project _project() => Project(
  id: const ProjectId('face-project'),
  name: 'Face',
  createdAt: DateTime.utc(2026, 9, 24),
  tracks: [
    Track(
      id: const TrackId('face-track'),
      name: 'Video',
      cuts: [
        Cut(
          id: const CutId('face-cut'),
          name: 'Cut',
          duration: 12,
          canvasSize: const CanvasSize(width: 640, height: 360),
          guides: CutGuides(
            guides: [
              DrawingGuide(
                id: const GuideId('face-guide'),
                name: 'Sym',
                shape: SymmetryShape(
                  axis: GuideAxis(
                    origin: CanvasPoint(x: 320, y: 180),
                    angleDegrees: 90,
                  ),
                ),
              ),
            ],
          ),
          layers: [
            Layer(
              id: const LayerId('face-cel'),
              name: 'A',
              frames: [
                Frame(
                  id: const FrameId('face-drawing'),
                  duration: 1,
                  strokes: const [],
                ),
              ],
              timeline: {
                0: const TimelineExposure.drawing(
                  FrameId('face-drawing'),
                  length: 4,
                ),
              },
            ),
          ],
        ),
      ],
    ),
  ],
);
