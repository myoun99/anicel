import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_frame_count_settings.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/frame_count_field.dart';

/// 🗣️I-24 (유저 2026-09-14): 「코마 수 설정창에서 기존처럼 프레임수로 정하는거랑
/// 추가로 초수+코마로 조절하는거 신설. 버튼으로 각각 옵션 변경가능. 초수+코마는
/// 특히 +를 텍스트로 쓰게한다거나 하지말고 초수랑 코마랑 제대로 칸 나눠서
/// 입력하게하고 사이에 + 텍스트만 넣기. 그리고 이 창은 알겠지만 숫자만
/// 입력가능하도록. 그리고 초수+코마 변경은 특히 여러곳에서 쓰일테니 공용화」.
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

  String textOf(WidgetTester tester, String key) => tester
      .widget<TextField>(find.byKey(ValueKey<String>(key)))
      .controller!
      .text;

  testWidgets('the shared field: frames, switched to seconds+frames and back, '
      'digits only', (tester) async {
    int? count;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FrameCountField(
            keyPrefix: 'n',
            label: 'Count',
            framesPerSecond: 24,
            onChanged: (value) => count = value,
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(const ValueKey<String>('n-field')), '30');
    expect(count, 30);

    await tester.tap(find.byKey(const ValueKey<String>('n-entry-seconds')));
    await tester.pump();
    expect(
      [textOf(tester, 'n-seconds-field'), textOf(tester, 'n-koma-field')],
      ['1', '6'],
      reason: 'what was typed carries across the switch',
    );
    expect(count, 30);

    await tester.enterText(
      find.byKey(const ValueKey<String>('n-seconds-field')),
      '2',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('n-koma-field')),
      '1+2a',
    );
    expect(
      textOf(tester, 'n-koma-field'),
      '12',
      reason: '「숫자만 입력가능하도록」 — and the + is never typed',
    );
    expect(count, 2 * 24 + 12);

    await tester.tap(find.byKey(const ValueKey<String>('n-entry-frames')));
    await tester.pump();
    expect(textOf(tester, 'n-field'), '60');
    expect(count, 60);
  });

  testWidgets('the N window applies a count typed as seconds+frames', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
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
    await tester.enterText(
      find.byKey(const ValueKey<String>('set-comma-n-seconds-field')),
      '1',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('set-comma-n-koma-field')),
      '2',
    );
    await tester.tap(find.byKey(const ValueKey<String>('set-comma-n-apply')));
    await tester.pumpAndSettle();

    final block = s.activeLayer!.timeline.entries.first;
    expect((block.key, block.value.length), (0, fps + 2));
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
