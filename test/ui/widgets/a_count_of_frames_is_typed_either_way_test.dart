import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_frame_count_settings.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/drag_value_label.dart';
import 'package:anicel/src/ui/widgets/frame_count_field.dart';
import 'package:anicel/src/ui/widgets/window_number.dart';

import '../../helpers/app_shortcuts.dart';
import '../../helpers/number_pad_keyboard.dart';

/// 🗣️I-24 (유저 2026-09-14): 「코마 수 설정창에서 기존처럼 프레임수로 정하는거랑
/// 추가로 초수+코마로 조절하는거 신설. 버튼으로 각각 옵션 변경가능. 초수+코마는
/// 특히 +를 텍스트로 쓰게한다거나 하지말고 초수랑 코마랑 제대로 칸 나눠서
/// 입력하게하고 사이에 + 텍스트만 넣기. 그리고 이 창은 알겠지만 숫자만
/// 입력가능하도록. 그리고 초수+코마 변경은 특히 여러곳에서 쓰일테니 공용화」 —
/// each number the window number (🗣️F-507-Q1 「칸마다 드래그 숫자 — 전환은
/// 그대로」).
void main() {
  // Which entry the window opens on is an app-wide value that outlives a
  // test: each starts from the product default.
  void resetEntry() =>
      AppFrameCountSettings.settings.value = const AppFrameCountSettings();
  setUp(resetEntry);
  tearDown(resetEntry);

  test('seconds+frames and frames are one count, both ways', () {
    for (final fps in [24, 30]) {
      for (final frames in [0, 1, fps - 1, fps, fps + 6, fps * 3 + 5]) {
        final split = durationSecondsAndFrames(frames, fps);
        expect(
          framesOfSecondsAndFrames(split.seconds, split.frames, fps),
          frames,
          reason: '$frames at $fps',
        );
      }
    }
    expect(framesOfSecondsAndFrames(1, 6, 24), 30);
  });

  /// The shared field at 24 fps over a count its host keeps, as a count
  /// window keeps it; the answer reads the count kept.
  Future<int? Function()> pumpField(
    WidgetTester tester, {
    required int? count,
    FrameCountEntry entry = FrameCountEntry.frames,
  }) async {
    var kept = count;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => FrameCountField(
              keyPrefix: 'n',
              label: 'Count',
              framesPerSecond: 24,
              count: kept,
              initialEntry: entry,
              onChanged: (value) => setState(() => kept = value),
            ),
          ),
        ),
      ),
    );
    return () => kept;
  }

  String shown(WidgetTester tester, String key) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byType(Text),
        ),
      )
      .data!;

  (String, String) split(WidgetTester tester) =>
      (shown(tester, 'n-seconds-field'), shown(tester, 'n-koma-field'));

  Future<void> press(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pump();
  }

  testWidgets('the shared field: frames, switched to seconds+frames and back, '
      'each number typed on its own', (tester) async {
    final count = await pumpField(tester, count: 30);
    expect(shown(tester, 'n-field'), '30');

    await press(tester, 'n-entry-seconds');
    expect(
      split(tester),
      ('1', '6'),
      reason: 'the count shows across the switch',
    );
    expect(count(), 30);

    await typeOnThePad(tester, 'n-seconds-field', '2');
    expect((count(), split(tester)), (2 * 24 + 6, ('2', '6')));
    await typeOnThePad(tester, 'n-koma-field', '12');
    expect(count(), 2 * 24 + 12);

    await press(tester, 'n-entry-frames');
    expect(shown(tester, 'n-field'), '60');
    expect(count(), 60);
  });

  // 🗣️F-507-Q1: 「코마를 끌어 fps 를 넘기면 초로 올라간다」.
  testWidgets('the koma counts on past the rate into the seconds and back; '
      'the seconds stop at zero keeping the koma, the count at zero', (
    tester,
  ) async {
    final count = await pumpField(
      tester,
      count: 23,
      entry: FrameCountEntry.secondsPlusFrames,
    );
    expect(split(tester), ('0', '23'));

    await press(tester, 'n-koma-field-step-up');
    expect((count(), split(tester)), (24, ('1', '0')));
    await press(tester, 'n-koma-field-step-down');
    expect((count(), split(tester)), (23, ('0', '23')));

    await typeOnThePad(tester, 'n-koma-field', '30');
    expect(
      (count(), split(tester)),
      (30, ('1', '6')),
      reason: 'a koma typed past the rate carries too',
    );

    await press(tester, 'n-seconds-field-step-down');
    expect((count(), split(tester)), (6, ('0', '6')));
    await press(tester, 'n-seconds-field-step-down');
    expect((count(), split(tester)), (6, ('0', '6')));

    for (var step = 0; step < 7; step += 1) {
      await press(tester, 'n-koma-field-step-down');
    }
    expect((count(), split(tester)), (0, ('0', '0')));
  });

  // The way a field stood empty where the blocks do not agree on a length
  // (I-24-open-entry).
  testWidgets('with no count to show, each number reads the mark for none, '
      'and a move counts from zero', (tester) async {
    final count = await pumpField(tester, count: null);
    expect(shown(tester, 'n-field'), WindowNumber.noAgreedNumber);
    await press(tester, 'n-field-step-up');
    expect((count(), shown(tester, 'n-field')), (1, '1'));

    // A field of its own, opened on the other entry.
    await tester.pumpWidget(const SizedBox());
    final split24 = await pumpField(
      tester,
      count: null,
      entry: FrameCountEntry.secondsPlusFrames,
    );
    expect(
      split(tester),
      (WindowNumber.noAgreedNumber, WindowNumber.noAgreedNumber),
    );
    await press(tester, 'n-seconds-field-step-up');
    expect((split24(), split(tester)), (24, ('1', '0')));

    await tester.pumpWidget(const SizedBox());
    final komaFirst = await pumpField(
      tester,
      count: null,
      entry: FrameCountEntry.secondsPlusFrames,
    );
    await press(tester, 'n-koma-field-step-up');
    expect((komaFirst(), split(tester)), (1, ('0', '1')));
  });

  testWidgets('a drag along a number moves it — the seconds a second a unit', (
    tester,
  ) async {
    final count = await pumpField(
      tester,
      count: 30,
      entry: FrameCountEntry.secondsPlusFrames,
    );
    await tester.drag(
      find.byKey(const ValueKey<String>('n-seconds-field')),
      const Offset(16, 0),
    );
    await tester.pumpAndSettle();
    expect((count(), split(tester)), (3 * 24 + 6, ('3', '6')));

    await tester.drag(
      find.byKey(const ValueKey<String>('n-seconds-field')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();
    expect((count(), split(tester)), (6, ('0', '6')));
  });

  // 🗣️F-507: 「자동이름조정 왼쪽정렬인거 이상하니 중앙정렬」 — every window
  // number stands in the middle.
  testWidgets('the numbers stand in the middle of the field, either way', (
    tester,
  ) async {
    await pumpField(tester, count: 30);
    final middle = tester.getCenter(find.byType(FrameCountField)).dx;
    double centreOf(Finder finder) => tester.getCenter(finder).dx;
    expect(centreOf(find.byType(DragValueLabel)), moreOrLessEquals(middle));

    await press(tester, 'n-entry-seconds');
    final [seconds, koma] = [
      for (final element in find.byType(DragValueLabel).evaluate())
        centreOf(find.byWidget(element.widget)),
    ];
    expect((seconds + koma) / 2, moreOrLessEquals(middle));
    expect(seconds, lessThan(middle));
    expect(centreOf(find.text('+')), moreOrLessEquals(middle));
  });

  testWidgets('the N window applies a count typed as seconds+frames', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    // 5 is anicel's key for the N window; Clip Studio's layout has none
    // (F-417-Q1).
    await useAnicelKeys(tester);
    await tester.pumpAndSettle();
    final s = tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    final fps = s.projectSettings.projectFrameRate.countingBase;

    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('set-comma-n-entry-seconds')),
    );
    await tester.pump();
    await typeOnThePad(tester, 'set-comma-n-seconds-field', '1');
    await typeOnThePad(tester, 'set-comma-n-koma-field', '2');
    await tester.tap(find.byKey(const ValueKey<String>('set-comma-n-apply')));
    await tester.pumpAndSettle();

    final block = s.activeLayer!.timeline.entries.first;
    expect((block.key, block.value.length), (0, fps + 2));
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('Enter applies the N window — the keyboard opens on Apply', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await useAnicelKeys(tester);
    await tester.pumpAndSettle();
    final s = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('set-comma-n-field-step-up')),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('set-comma-n-dialog')),
      findsNothing,
    );
    final block = s.activeLayer!.timeline.entries.first;
    expect((block.key, block.value.length), (0, 2));
    s.playbackRig.prerenderScheduler.cancel();
  });

  // 🗣️I-24-open-entry-Q1 (유저 2026-10-01): 「마지막에 쓴 방식으로 연다」.
  testWidgets('the N window opens on the entry it was last switched to', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    // 5 is anicel's key for the N window; Clip Studio's layout has none
    // (F-417-Q1).
    await useAnicelKeys(tester);
    await tester.pumpAndSettle();
    final s = tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
    // The window opens over a block to apply to, as in the test above.
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    final seconds = find.byKey(
      const ValueKey<String>('set-comma-n-seconds-field'),
    );
    Future<void> openAndClose(void Function() whileOpen) async {
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.pumpAndSettle();
      whileOpen();
      await tester.tap(find.text(AppText.strings.commonCancel));
      await tester.pumpAndSettle();
    }

    await openAndClose(() {
      expect(seconds, findsNothing, reason: 'a first opening is on frames');
    });

    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('set-comma-n-entry-seconds')),
    );
    await tester.pump();
    await tester.tap(find.text(AppText.strings.commonCancel));
    await tester.pumpAndSettle();
    expect(
      AppFrameCountSettings.settings.value.lastEntry,
      FrameCountEntry.secondsPlusFrames,
      reason: 'the switch itself is what is remembered — a cancel keeps it',
    );

    await openAndClose(() {
      expect(seconds, findsOneWidget, reason: 'it opens where it was left');
    });
    s.playbackRig.prerenderScheduler.cancel();
  });
}
