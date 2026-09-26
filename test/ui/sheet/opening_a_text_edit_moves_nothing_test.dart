import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/app_faces.dart';
import '../../helpers/device_viewport.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/exposure_memo.dart';
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
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppTypography;
import 'package:anicel/src/ui/timesheet_tab_host.dart';

/// 🚨OPENING A TEXT EDIT MOVES NOTHING (F-188, 유저 2026-09-26: 「액션란
/// 메모 시작할때 ui가 써져있는거랑 다름. 뭔가 이동되는느낌? 최대한
/// 안움직이게하고 ui심플하게. 지금 실루엣 라인이 두개나있음」).
///
/// A tap on the printed words puts the field ON them: the field lays the
/// words out as the printer did — its face, its size, its width, its line
/// heights — and draws nothing round them. So the page with the editor
/// open is the page without it, but for the caret — on every sheet the one
/// editor serves, at any zoom, whatever the platform's text scale.
void main() {
  const boundary = ValueKey<String>('screen');
  const words = '하야토가 문을 박차고 뛰어든다. 숨을 고르며 방 안을 천천히 '
      '둘러본다';

  Future<Uint8List> shoot(WidgetTester tester) async {
    await tester.pumpAndSettle();
    final render = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundary),
    );
    final ratio = tester.view.devicePixelRatio;
    return (await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: ratio);
      final data = await image.toByteData();
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
  }

  /// The caret the open field shows, on the screen.
  Rect caretOf(WidgetTester tester, Finder field) {
    final editable = tester
        .state<EditableTextState>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        )
        .renderEditable;
    final local = editable.getLocalRectForCaret(editable.selection!.extent);
    return Rect.fromPoints(
      editable.localToGlobal(local.topLeft),
      editable.localToGlobal(local.bottomRight),
    ).inflate(3);
  }

  /// How far a pixel may read apart without anything having moved: the
  /// field's words are drawn in a picture layer of their own, and a glyph's
  /// edge there comes out up to 15 levels from the same edge in the page's
  /// picture (measured 2026-09-26, the field's origin equal to the print's
  /// to the sixth decimal). A move of a tenth of a pixel is 25.
  const rounding = 24;

  /// Opens the field over [box] — a rect on the screen — and returns every
  /// device pixel round the box that the opening changed, the caret aside.
  Future<List<Offset>> openAndCompare(
    WidgetTester tester, {
    required Rect box,
    required Finder field,
  }) async {
    final screen = tester.getTopLeft(find.byKey(boundary));
    final closed = await shoot(tester);
    await tester.tapAt(box.center);
    await tester.pumpAndSettle();
    expect(field, findsOneWidget);
    final open = await shoot(tester);
    final caret = caretOf(tester, field);

    final ratio = tester.view.devicePixelRatio;
    final width =
        (tester.getSize(find.byKey(boundary)).width * ratio).round();
    final region = box.inflate(6).shift(-screen);
    return [
      for (var y = (region.top * ratio).floor(); y < region.bottom * ratio; y++)
        for (
          var x = (region.left * ratio).floor();
          x < region.right * ratio;
          x++
        )
          if (!caret.contains(Offset(x + 0.5, y + 0.5) / ratio + screen) &&
              [
                for (var c = 0; c < 4; c++)
                  (closed[(y * width + x) * 4 + c] -
                              open[(y * width + x) * 4 + c])
                          .abs() >
                      rounding,
              ].contains(true))
            Offset(x + 0.5, y + 0.5) / ratio,
    ];
  }

  group('the conte\'s ACTION', () {
    Project project() => Project(
      id: const ProjectId('conte-project'),
      name: 'Conte',
      createdAt: DateTime.utc(2026, 9, 26),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Video',
          cuts: [
            Cut(
              id: const CutId('39'),
              name: '39',
              duration: 10,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: [
                Layer(
                  id: const LayerId('sb'),
                  name: 'SB',
                  kind: LayerKind.storyboard,
                  frames: [
                    Frame(
                      id: const FrameId('sb-0'),
                      duration: 1,
                      strokes: const [],
                    ),
                  ],
                  timeline: const {
                    0: TimelineExposure.drawing(
                      FrameId('sb-0'),
                      length: 10,
                      memo: ExposureMemo(actionMemo: words),
                    ),
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );

    /// The panel at [zoom], the platform's text scaled by [textScale];
    /// returns the cell's ACTION box on the screen.
    Future<Rect> pumpConte(
      WidgetTester tester, {
      double zoom = 1,
      double textScale = 1,
    }) async {
      await loadTheAppFaces();
      final session = EditorSessionManager(initialProject: project());
      addTearDown(session.dispose);
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: RepaintBoundary(
                  key: boundary,
                  child: ConteTabHost(
                    session: session,
                    thumbnails: null,
                    viewport: seedFromRender(
                      tester,
                      CanvasViewport(zoom: zoom),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final page = layoutConteSheet(
        buildConteSheetSource(session.repository.requireProject()),
        metrics: ConteSheetMetrics(
          cameraAspect: session.camera.cameraFrameAspect,
        ),
      ).first;
      final cell = page.cells.single;
      final m = page.metrics;
      final paper = Rect.fromLTRB(
        cell.actionRect.left,
        m.rowTop(cell.rowOnPage),
        cell.actionRect.right,
        m.rowTop(cell.rowOnPage + cell.source.rowSpan),
      );
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey<String>('conte-form-paint')),
      );
      return Rect.fromLTRB(
        origin.dx + zoom * paper.left,
        origin.dy + zoom * paper.top,
        origin.dx + zoom * paper.right,
        origin.dy + zoom * paper.bottom,
      );
    }

    final field = find.byKey(const ValueKey<String>('conte-action-field'));

    testWidgets('the page with the editor open is the page without it, but '
        'for the caret', (tester) async {
      final box = await pumpConte(tester);
      expect(
        await openAndCompare(tester, box: box, field: field),
        isEmpty,
      );
    });

    testWidgets('at a zoom the words are set at the printed size and shown '
        'as the paper is', (tester) async {
      final box = await pumpConte(tester, zoom: 1.37);
      expect(
        await openAndCompare(tester, box: box, field: field),
        isEmpty,
      );
    });

    testWidgets('the platform\'s text scale reaches neither the print nor '
        'the field', (tester) async {
      final box = await pumpConte(tester, textScale: 1.3);
      expect(
        await openAndCompare(tester, box: box, field: field),
        isEmpty,
      );
    });
  });

  group('the timesheet\'s header and memo', () {
    late EditorSessionManager session;

    Future<void> pumpSheet(WidgetTester tester) async {
      await loadTheAppFaces();
      session = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(session.dispose);
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            // The face the app's theme gives every word — the one the sheet
            // prints in.
            body: DefaultTextStyle.merge(
              style: const TextStyle(
                fontFamily: AppTypography.bundledFamily,
                fontFamilyFallback: AppTypography.bundledFallback,
              ),
              child: RepaintBoundary(
                key: boundary,
                child: TimesheetTabHost(
                  session: session,
                  continuous: false,
                  onContinuousChanged: (_) {},
                  viewport: CanvasViewport(),
                  onViewportChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final field = find.byKey(
      const ValueKey<String>('timesheet-header-edit-field'),
    );

    testWidgets('a header box: its value is typed on its printed glyphs', (
      tester,
    ) async {
      await pumpSheet(tester);
      final box = tester.getRect(
        find.byKey(const ValueKey<String>('timesheet-header-edit-title-p0')),
      );
      expect(
        await openAndCompare(tester, box: box, field: field),
        isEmpty,
      );
    });

    testWidgets('the memo band: its lines are typed on their printed glyphs', (
      tester,
    ) async {
      await pumpSheet(tester);
      session.cutVerbs.updateActiveCutNote(words);
      await tester.pumpAndSettle();
      final box = tester.getRect(
        find.byKey(const ValueKey<String>('timesheet-memo-edit-p0')),
      );
      expect(
        await openAndCompare(tester, box: box, field: field),
        isEmpty,
      );
    });
  });
}
