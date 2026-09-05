import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_preview.dart';

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
}
