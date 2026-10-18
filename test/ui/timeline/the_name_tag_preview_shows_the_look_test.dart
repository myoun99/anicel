import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_preview.dart';

import '../../helpers/named_finders.dart';

/// The name tag's live preview on its group header — nothing named it
/// (2026-09-05).
///
/// 🚨It shows the LOOK, never the content: 「프리뷰는 그냥 어떤식으로 될지
/// 확인만 하는거니까」. And the box keeps its shape at every size — the rail
/// row is 24px tall while the tag's real fontSize is 34, so this is a
/// SILHOUETTE, not a scaled render.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    String name = '名前',
    String line = 'セリフ',
    SeNameTag tag = const SeNameTag(),
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 200,
          height: 24,
          child: SeNameTagLanePreview(name: name, line: line, tag: tag),
        ),
      ),
    ),
  );

  TextStyle styleOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!;

  testWidgets('it draws the name and the dialogue sample', (tester) async {
    await pump(tester);

    expect(find.text('名前'), findsOneWidget);
    expect(find.text('セリフ'), findsOneWidget);
  });

  testWidgets('⛔an EMPTY line draws none — which is what the Show Dialogue '
      'member turning off looks like', (tester) async {
    await pump(tester, line: '');

    expect(find.text('名前'), findsOneWidget);
    expect(find.text('セリフ'), findsNothing);
    expect(
      find.byType(Text),
      findsOneWidget,
      reason: 'not an EMPTY Text beside it — the row draws one thing',
    );
  });

  testWidgets('🚨the type size is the RAIL\'s, not the tag\'s — the row is '
      '24px tall and the real tag is 34pt, so this is a silhouette', (
    tester,
  ) async {
    await pump(tester, tag: const SeNameTag(style: TextCelStyle(fontSize: 34)));

    expect(styleOf(tester, '名前').fontSize, 10);
  });

  testWidgets('🚨BOLD carries through, because the point of the preview is '
      'the look', (tester) async {
    // ⚠️The tag's own default IS bold (the name reads on the picture), so
    // the un-bold case has to be asked for.
    await pump(tester, tag: const SeNameTag(style: TextCelStyle(bold: false)));
    expect(styleOf(tester, '名前').fontWeight, FontWeight.w400);

    await pump(tester, tag: const SeNameTag(style: TextCelStyle(bold: true)));
    expect(styleOf(tester, '名前').fontWeight, FontWeight.w700);
  });

  testWidgets('🗣️the LEAN carries through, on both runs '
      '(text-letters-lean-and-underline-Q1: 「일곱 전부」)', (tester) async {
    await pump(tester);
    expect(styleOf(tester, '名前').fontStyle, FontStyle.normal);

    await pump(
      tester,
      tag: const SeNameTag(
        style: TextCelStyle(italic: true),
        lineStyle: TextCelStyle(italic: true),
      ),
    );
    expect(styleOf(tester, '名前').fontStyle, FontStyle.italic);
    expect(styleOf(tester, 'セリフ').fontStyle, FontStyle.italic);
  });

  testWidgets('🗣️the LINES its letters wear are drawn over each run — under '
      'it, and through its middle, in its ink', (tester) async {
    await pump(tester);
    expect(_linesOver(tester, '名前'), isNot(paints..rect()));

    await pump(
      tester,
      tag: const SeNameTag(
        style: TextCelStyle(underline: true, color: 0xFF00FF00),
        lineStyle: TextCelStyle(strikethrough: true, color: 0xFFFF0000),
      ),
    );
    final name = tester.getSize(find.text('名前'));
    final line = tester.getSize(find.text('セリフ'));

    expect(
      _linesOver(tester, '名前'),
      paints..rect(
        rect: Rect.fromLTWH(0, name.height - 1, name.width, 1),
        color: const Color(0xFF00FF00),
      ),
    );
    expect(
      _linesOver(tester, 'セリフ'),
      paints..rect(
        rect: Rect.fromLTWH(0, (line.height - 1) / 2, line.width, 1),
        color: const Color(0xFFFF0000),
      ),
    );
  });

  testWidgets('the INK carries through', (tester) async {
    await pump(
      tester,
      tag: const SeNameTag(style: TextCelStyle(color: 0xFF00FF00)),
    );

    expect(styleOf(tester, '名前').color, const Color(0xFF00FF00));
  });

  testWidgets('🚨letter spacing is SCALED with the type — a full-size gap '
      'at a third of the size would tear the silhouette apart', (tester) async {
    await pump(
      tester,
      tag: const SeNameTag(style: TextCelStyle(letterSpacing: 8)),
    );

    expect(styleOf(tester, '名前').letterSpacing, 2);
  });

  testWidgets('zero letter spacing stays UNSET rather than becoming a zero '
      'override', (tester) async {
    await pump(tester);

    expect(styleOf(tester, '名前').letterSpacing, isNull);
  });

  testWidgets('the name and the DIALOGUE carry their own styles — they are '
      'two settings, not one', (tester) async {
    await pump(
      tester,
      tag: const SeNameTag(
        style: TextCelStyle(color: 0xFF00FF00),
        lineStyle: TextCelStyle(color: 0xFFFF0000),
      ),
    );

    expect(styleOf(tester, '名前').color, const Color(0xFF00FF00));
    expect(styleOf(tester, 'セリフ').color, const Color(0xFFFF0000));
  });

  testWidgets('the name CLIPS while the dialogue ellipsises — the box is a '
      'shape and the line is a sentence', (tester) async {
    await pump(tester);

    expect(tester.widget<Text>(find.text('名前')).overflow, TextOverflow.clip);
    expect(
      tester.widget<Text>(find.text('セリフ')).overflow,
      TextOverflow.ellipsis,
    );
  });

  // 🗣️xsheet-s-row-name-tag-overflow-Q1 (유저 2026-09-29): 「세로쓰기 — 시트의
  // 다른 글자처럼」. ↩️On the sheet the preview stayed one line across a
  // 23px column and ran 27px past it.
  group('on the SHEET', () {
    VerticalWritingText written(WidgetTester tester, String text) =>
        tester.widget<VerticalWritingText>(
          find.byWidgetPredicate(
            (widget) => widget is VerticalWritingText && widget.text == text,
          ),
        );

    testWidgets('the box and the dialogue are written DOWN the column, as '
        'the sheet\'s other words are, and keep their look', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 23,
                height: 160,
                child: SeNameTagLanePreview(
                  name: '名前',
                  line: 'セリフ',
                  tag: SeNameTag(
                    style: TextCelStyle(bold: true, color: 0xFF00FF00),
                    lineStyle: TextCelStyle(color: 0xFFFF0000),
                  ),
                  axis: Axis.vertical,
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull, reason: 'no overflow');
      final name = written(tester, '名前');
      expect(name.latinForm, VerticalLatinForm.upright);
      expect(name.style!.fontWeight, FontWeight.w700);
      expect(name.style!.color, const Color(0xFF00FF00));
      expect(written(tester, 'セリフ').style!.color, const Color(0xFFFF0000));
      final nameBox = tester.getRect(find.byWidget(name));
      final lineBox = tester.getRect(find.byWidget(written(tester, 'セリフ')));
      expect(
        lineBox.top,
        greaterThanOrEqualTo(nameBox.bottom),
        reason: 'the dialogue follows the box DOWN the column',
      );
      expect(nameBox.width, lessThanOrEqualTo(23));
    });

    testWidgets('🗣️a line under the letters runs DOWN the column on its '
        'RIGHT, as the canvas sets one (傍線), and one through them down its '
        'middle', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 23,
                height: 160,
                child: SeNameTagLanePreview(
                  name: '名前',
                  line: 'セリフ',
                  tag: SeNameTag(
                    style: TextCelStyle(underline: true),
                    lineStyle: TextCelStyle(strikethrough: true),
                  ),
                  axis: Axis.vertical,
                ),
              ),
            ),
          ),
        ),
      );
      final name = tester.getSize(find.byWidget(written(tester, '名前')));
      final line = tester.getSize(find.byWidget(written(tester, 'セリフ')));

      expect(
        _linesOver(tester, '名前'),
        paints..rect(rect: Rect.fromLTWH(name.width - 1, 0, 1, name.height)),
      );
      expect(
        _linesOver(tester, 'セリフ'),
        paints..rect(
          rect: Rect.fromLTWH((line.width - 1) / 2, 0, 1, line.height),
        ),
      );
    });

    testWidgets('🚨in the real sheet, the S row\'s name-tag group header '
        'holds its preview inside its column', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: _sRowProject())),
      );
      await tester.pumpAndSettle();
      Future<void> press(Finder button) async {
        final target = button.first;
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await press(find.named('timeline-lane-toggle-${_seId.value}'));
      await press(
        find.byKey(
          const ValueKey<String>('timeline-orientation-toggle-button'),
        ),
      );

      final preview = find.byKey(
        ValueKey<String>('xsheet-lane-group-preview-${_seId.value}-'
            'name-tag-group'),
      );
      expect(preview, findsOneWidget, reason: 'premise: the header is up');
      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(
        find.descendant(
          of: preview,
          matching: find.byType(VerticalWritingText),
        ),
        findsNWidgets(2),
        reason: 'the box and the dialogue sample, each written down',
      );
    });
  });

  testWidgets('on the RAIL the preview stands at the end of the slots it '
      'fills, centred across the row (R5 #7)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: _sRowProject())),
    );
    await tester.pumpAndSettle();
    final toggle = find.named('timeline-lane-toggle-${_seId.value}').first;
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    final preview = find.byKey(
      ValueKey<String>(
        'timeline-lane-group-preview-${_seId.value}-name-tag-group',
      ),
    );
    expect(preview, findsOneWidget, reason: 'premise: the header is up');
    final slots = tester.getRect(
      find.ancestor(of: preview, matching: find.byType(Align)).first,
    );
    final box = tester.getRect(preview);
    expect(
      box.width,
      lessThan(slots.width),
      reason: '⛔premise: the preview leaves room to stand in',
    );
    expect(box.right, moreOrLessEquals(slots.right, epsilon: 0.5));
    expect(box.center.dy, moreOrLessEquals(slots.center.dy, epsilon: 0.5));
  });
}

/// What draws the lines over the run of the preview that reads [text] —
/// along a row or down a column.
RenderObject _linesOver(WidgetTester tester, String text) =>
    tester.renderObject(
      find.ancestor(
        of: find.byWidgetPredicate(
          (widget) =>
              (widget is Text && widget.data == text) ||
              (widget is VerticalWritingText && widget.text == text),
        ),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.foregroundPainter is SeNameTagPreviewLines,
        ),
      ),
    );

const _seId = LayerId('tag-se');

/// A cut with one drawing row and a track S row — the name tag lives on
/// the S row's lanes.
Project _sRowProject() => Project(
  id: const ProjectId('tag-project'),
  name: 'Tag',
  createdAt: DateTime.utc(2026, 9, 29),
  tracks: [
    Track(
      id: const TrackId('tag-track'),
      name: 'Video',
      cuts: [
        Cut(
          id: const CutId('tag-cut'),
          name: 'Cut',
          duration: 12,
          canvasSize: const CanvasSize(width: 640, height: 360),
          layers: [
            Layer(
              id: const LayerId('tag-cel'),
              name: 'A',
              frames: const [],
              timeline: const {},
            ),
          ],
        ),
      ],
      seLayers: [
        Layer(
          id: _seId,
          name: 'S1',
          kind: LayerKind.se,
          frames: [
            Frame(
              id: const FrameId('tag-voice'),
              duration: 4,
              strokes: const [],
            ),
          ],
          timeline: {
            0: const TimelineExposure.drawing(FrameId('tag-voice'), length: 4),
          },
        ),
      ],
    ),
  ],
);
