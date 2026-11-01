import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/app_faces.dart';
import '../../helpers/conte_book.dart';
import '../../helpers/device_viewport.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_form.dart';
import 'package:anicel/src/models/envelope/cut_envelope_layout.dart';
import 'package:anicel/src/models/envelope/cut_envelope_source.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_document.dart'
    show sheetArtistMark;
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/brush/sheet_canvas_panel.dart'
    show SheetStrokeHold;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_paper.dart';
import 'package:anicel/src/ui/sheet/sheet_text_edit_layer.dart'
    show sheetTextEditFrameKey, sheetTextEditFrameWidth;
import 'package:anicel/src/ui/theme/app_theme.dart'
    show AppColors, buildAppTheme;
import 'package:anicel/src/ui/timesheet_tab_host.dart';

/// 🚨OPENING A TEXT EDIT MOVES NOTHING (F-188, 유저 2026-09-26: 「액션란
/// 메모 시작할때 ui가 써져있는거랑 다름. 뭔가 이동되는느낌? 최대한
/// 안움직이게하고 ui심플하게. 지금 실루엣 라인이 두개나있음」).
///
/// A tap on the printed words puts the field ON them: the field lays the
/// words out as the printer did — its face, its size, its width, its line
/// heights — and draws nothing round them. So the page with the editor
/// open is the page without it, but for the caret and the frame that says
/// so — on every sheet the one editor serves, at any zoom, whatever the
/// platform's text scale.
///
/// 🗣️F-543 (2026-11-02): 「제대로 수정중인지 모르겠음. 그냥 오버레이식으로
/// 보여주도록? 지금처럼 보여지는 텍스트랑 편집들어갈때랑 패딩같은거
/// 안달라지는게 목표」 — the frame lies over all of it, on the box's own line.
///
/// 실기 (I-127, 2026-11-01): 「입력 중 앞 글자가 잘리고 위아래도 잘린다」 —
/// ⚠️in the app's theme, which is where a field takes its padding and its
/// focus frame from. ↩️These ran in a bare `MaterialApp`, which has neither,
/// and stayed green over a field that lay 9 units off its print.
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
  /// device pixel round the box that the opening changed, the caret and the
  /// frame on the box's line aside.
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
    final frame = tester.getRect(find.byKey(sheetTextEditFrameKey));
    expect(
      frame,
      rectMoreOrLessEquals(box.inflate(sheetTextEditFrameWidth / 2)),
    );

    final ratio = tester.view.devicePixelRatio;
    final width =
        (tester.getSize(find.byKey(boundary)).width * ratio).round();
    // The line's edges lie between device pixels: each spills into one.
    final ring = frame.inflate(1 / ratio);
    final inside = frame.deflate(sheetTextEditFrameWidth + 1 / ratio);

    /// The colour [at] — a point on the screen — shows in [shot], as ARGB.
    int colourAt(Uint8List shot, Offset at) {
      final pixel = (at - screen) * ratio;
      final from = (pixel.dy.floor() * width + pixel.dx.floor()) * 4;
      return shot[from + 3] << 24 |
          shot[from] << 16 |
          shot[from + 1] << 8 |
          shot[from + 2];
    }

    const line = sheetTextEditFrameWidth / 2;
    for (final edge in [
      Offset(frame.center.dx, frame.top + line),
      Offset(frame.center.dx, frame.bottom - line),
      Offset(frame.left + line, frame.center.dy),
      Offset(frame.right - line, frame.center.dy),
    ]) {
      expect(
        colourAt(open, edge),
        AppColors.accent.toARGB32(),
        reason: 'the frame stands whole, over the paper, on the box\'s line',
      );
    }

    final region = box.inflate(6).shift(-screen);
    return [
      for (var y = (region.top * ratio).floor(); y < region.bottom * ratio; y++)
        for (
          var x = (region.left * ratio).floor();
          x < region.right * ratio;
          x++
        )
          if (Offset(x + 0.5, y + 0.5) / ratio + screen case final at
              when !caret.contains(at) &&
                  !(ring.contains(at) && !inside.contains(at)) &&
                  [
                    for (var c = 0; c < 4; c++)
                      (closed[(y * width + x) * 4 + c] -
                                  open[(y * width + x) * 4 + c])
                              .abs() >
                          rounding,
                  ].contains(true))
            at - screen,
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
          theme: buildAppTheme(),
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
                      onConteBody(session, CanvasViewport(zoom: zoom)),
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
        m.rowTop(cell.rowOnPage + cell.rowSpan),
      );
      final origin = conteBodyTopLeft(tester);
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

  group('the timesheet\'s memo', () {
    late EditorSessionManager session;

    Future<void> pumpSheet(WidgetTester tester) async {
      await loadTheAppFaces();
      session = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(session.dispose);
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: TimesheetTabHost(
                session: session,
                viewport: CanvasViewport(),
                onViewportChanged: (_) {},
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

    testWidgets('the memo band: its lines are typed on their printed glyphs', (
      tester,
    ) async {
      await pumpSheet(tester);
      session.cutVerbs.updateActiveCutNote(page: 0, note: words);
      await tester.pumpAndSettle();
      final box = tester.getRect(
        find.byKey(const ValueKey<String>('timesheet-memo-edit-p0')),
      );
      expect(
        await openAndCompare(tester, box: box, field: field),
        isEmpty,
      );
    });

    testWidgets('the name box: its one line is typed on its printed glyphs, '
        'centred as printed (I-112)', (tester) async {
      await pumpSheet(tester);
      session.cutVerbs.setCutStaffName(
        session.activeCutId!,
        sheetArtistMark,
        '大川ユキ',
      );
      await tester.pumpAndSettle();
      final box = tester.getRect(
        find.byKey(const ValueKey<String>('timesheet-name-edit-p0')),
      );
      expect(
        await openAndCompare(tester, box: box, field: field),
        isEmpty,
      );
    });

    // 🗣️I-127-Q4 (유저 2026-11-01): 「글자를 줄여 칸에 맞춘다」 — the one
    // line-box law, this sheet's name as the envelope's.
    testWidgets('the name box: a name too long for it, shrunk, is typed on '
        'its printed glyphs', (tester) async {
      await pumpSheet(tester);
      session.cutVerbs.setCutStaffName(
        session.activeCutId!,
        sheetArtistMark,
        'tanaka yoshiyuki tanaka',
      );
      await tester.pumpAndSettle();
      final box = tester.getRect(
        find.byKey(const ValueKey<String>('timesheet-name-edit-p0')),
      );
      expect(
        await openAndCompare(tester, box: box, field: field),
        isEmpty,
      );
    });
  });

  /// 🗣️I-127-Q1 (유저 2026-10-25): 「봉투 용지 패널에도 넣고」 — the
  /// envelope's staff boxes, a line set as its form sets it: left, centred
  /// or right.
  group('the envelope\'s staff box', () {
    const key = LayerMark(process: LayerProcess.key);
    CutEnvelopeForm formOn(int paperArgb) => CutEnvelopeForm(
      id: 'aligned',
      name: 'Aligned',
      aspectRatio: 2,
      paperArgb: paperArgb,
      boxes: [
        for (final (i, align) in [
          (0, EnvelopeAlign.left),
          (1, EnvelopeAlign.center),
          (2, EnvelopeAlign.right),
        ])
          EnvelopeBox(
            id: 'staff-$i',
            rect: EnvelopeRect(
              x: 0.05,
              y: 0.1 + i * 0.3,
              width: 0.6,
              height: 0.2,
            ),
            contentKind: EnvelopeContentKind.text,
            binding: '{staff.${key.keySlug}.name}',
            contentSize: 20,
            contentAlign: align,
          ),
      ],
    );

    Future<void> pumpEnvelope(
      WidgetTester tester, {
      int paperArgb = 0xFFFFFFFF,
      String name = '大川ユキ',
    }) async {
      await loadTheAppFaces();
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final hold = SheetStrokeHold(brushInput: (_) {});
      addTearDown(hold.dispose);
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: CutEnvelopePaper(
                session: session,
                layout: CutEnvelopeLayout.fit(
                  form: formOn(paperArgb),
                  paperWidth: 1000,
                  paperHeight: 500,
                ),
                source: CutEnvelopeSource(staff: {key.keySlug: name}),
                owner: session.activeCutId,
                viewport: CanvasViewport(),
                strokeHold: hold,
                cacheInvalidationSink:
                    session.renderCaches.cacheInvalidationHub,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final field = find.byKey(
      const ValueKey<String>('cut-envelope-edit-field'),
    );

    for (final (i, align) in [(0, 'left'), (1, 'centred'), (2, 'right')]) {
      testWidgets('a box set $align: its one line is typed on its printed '
          'glyphs', (tester) async {
        await pumpEnvelope(tester);
        final box = tester.getRect(
          find.byKey(ValueKey<String>('cut-envelope-staff-$i-edit')),
        );
        expect(
          await openAndCompare(tester, box: box, field: field),
          isEmpty,
        );
      });
    }

    // 실기 (I-127, 2026-11-01): 「입력 칸은 바탕이 흰색」.
    testWidgets('on a form\'s kraft the printed words stand down on the kraft '
        '— no white patch', (tester) async {
      await pumpEnvelope(tester, paperArgb: 0xFFE3D5B0);
      final box = tester.getRect(
        find.byKey(const ValueKey<String>('cut-envelope-staff-0-edit')),
      );
      expect(await openAndCompare(tester, box: box, field: field), isEmpty);
    });

    // 🗣️I-127-Q4 (유저 2026-11-01): 「글자를 줄여 칸에 맞춘다」.
    const long =
        'tanaka yoshiyuki tanaka yoshiyuki tanaka yoshiyuki tanaka yoshiyuki '
        'tanaka yoshiyuki tanaka yoshiyuki';

    for (final (i, align) in [(0, 'left'), (1, 'centred'), (2, 'right')]) {
      testWidgets('a name too long for a box set $align: shrunk, it is typed '
          'on its printed glyphs', (tester) async {
        await pumpEnvelope(tester, name: long);
        final box = tester.getRect(
          find.byKey(ValueKey<String>('cut-envelope-staff-$i-edit')),
        );
        expect(await openAndCompare(tester, box: box, field: field), isEmpty);
      });
    }

    testWidgets('a press in the open field is the field\'s, under the frame; '
        'the frame goes as the field does', (tester) async {
      await pumpEnvelope(tester);
      final box = tester.getRect(
        find.byKey(const ValueKey<String>('cut-envelope-staff-0-edit')),
      );
      await tester.tapAt(box.center);
      await tester.pumpAndSettle();
      final editable = tester
          .state<EditableTextState>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .renderEditable;

      await tester.tapAt(tester.getTopLeft(field) + const Offset(1, 4));
      await tester.pumpAndSettle();
      expect(editable.selection?.baseOffset, 0, reason: 'the caret went there');

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.byKey(sheetTextEditFrameKey), findsNothing);
    });

    testWidgets('a name typed past its box shrinks as it goes: it scrolls no '
        'glyph out, and the caret stays in the box', (tester) async {
      await pumpEnvelope(tester);
      final box = tester.getRect(
        find.byKey(const ValueKey<String>('cut-envelope-staff-0-edit')),
      );
      await tester.tapAt(box.center);
      await tester.pumpAndSettle();
      await tester.enterText(field, long);
      await tester.pumpAndSettle();

      final editable = tester
          .state<EditableTextState>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .renderEditable;
      expect(editable.maxScrollExtent, 0);
      expect(editable.offset.pixels, 0);
      expect(box.contains(caretOf(tester, field).deflate(3).center), isTrue);
    });
  });
}
