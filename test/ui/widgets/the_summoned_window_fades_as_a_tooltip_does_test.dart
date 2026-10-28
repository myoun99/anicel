import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';

/// 🚨THE SUMMONED WINDOW KEEPS FLUTTER'S TOOLTIP'S TIME.
///
/// The window every tooltip in the app summons ([SummonedTooltip]) says its
/// rules are Flutter's and only the holder is new. Two of them were not: a
/// press on the target, and a hover from one target onto the next, tore the
/// window down at once where Flutter's tooltip fades out over 75ms.
/// 🧪Measured 2026-10-25 (board `frame-panels-build-in-one-frame`).
///
/// So every case below is run three times — over two of Flutter's own
/// tooltips, over two [AppTooltip]s and over two icon buttons, the last two
/// summoning the window — and all three must read the same opacity, frame by
/// frame. ↩️The reference was [AppTooltip] while it was Flutter's line for
/// line; it summons the window too since 2026-10-25. Each case also says it
/// measured a fade, so runs that agree on nothing being shown prove nothing.
void main() {
  Future<List<String>> run(
    WidgetTester tester, {
    required _Holder holder,
    required Future<void> Function(_Scene scene) act,
  }) async {
    Widget box(String name) => SizedBox(
      key: ValueKey<String>(name),
      width: 40,
      height: 40,
      child: const ColoredBox(color: Colors.red),
    );
    Widget target(String name) => switch (holder) {
      _Holder.flutter => Tooltip(message: name, child: box(name)),
      _Holder.app => AppTooltip(message: name, child: box(name)),
      _Holder.face => AppIconButton(
        keyValue: name,
        tooltip: name,
        icon: const Icon(Icons.draw),
        onPressed: () {},
      ),
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              target('a'),
              const SizedBox(width: 80),
              target('b'),
              const SizedBox(
                key: ValueKey<String>('elsewhere'),
                width: 80,
                height: 40,
              ),
            ],
          ),
        ),
      ),
    );
    final scene = _Scene(tester);
    await act(scene);
    await scene.mouse?.removePointer();
    AppTooltip.dismissAllToolTips();
    await tester.pumpAndSettle();
    return scene.read;
  }

  final cases = <String, Future<void> Function(_Scene scene)>{
    'a hover moves on to the next target': (scene) async {
      await scene.hover('a');
      await scene.hover('b', settle: false);
      await scene.frames();
    },
    'a click on the target': (scene) async {
      await scene.hover('a');
      await scene.mouse!.down(scene.at('a'));
      await scene.frames();
      await scene.mouse!.up();
    },
    'a press elsewhere': (scene) async {
      await scene.hover('a');
      final finger = await scene.tester.startGesture(scene.at('elsewhere'));
      await scene.frames();
      await finger.up();
    },
    'every tooltip dismissed': (scene) async {
      await scene.hover('a');
      AppTooltip.dismissAllToolTips();
      await scene.frames();
    },
    'the mouse leaves': (scene) async {
      await scene.hover('a');
      await scene.mouse!.moveTo(scene.at('elsewhere'));
      await scene.frames(longer: true);
    },
    'the mouse comes back while it fades': (scene) async {
      await scene.hover('a');
      AppTooltip.dismissAllToolTips();
      await scene.frames(only: 2);
      await scene.mouse!.moveTo(scene.at('elsewhere'));
      await scene.tester.pump();
      await scene.hover('a', settle: false);
      await scene.frames(longer: true);
    },
    'a long press, then the lift': (scene) async {
      final finger = await scene.tester.startGesture(scene.at('a'));
      await scene.tester.pump(const Duration(milliseconds: 600));
      await scene.frames();
      await finger.up();
      await scene.frames(longer: true);
    },
  };

  testWidgets('a window another target took the place of is gone once it '
      'has faded — it is not kept beside the open one', (tester) async {
    final alive = SummonedTooltip.debugWindowsAlive;
    await run(
      tester,
      holder: _Holder.face,
      act: (scene) async {
        await scene.hover('a');
        await scene.hover('b', settle: false);
        await scene.frames();
        expect(SummonedTooltip.debugWindowsAlive, alive + 1);
      },
    );
    await tester.pumpWidget(const SizedBox());
    expect(SummonedTooltip.debugWindowsAlive, alive);
  });

  for (final MapEntry(key: name, value: act) in cases.entries) {
    testWidgets("$name — the window reads as Flutter's tooltip does", (
      tester,
    ) async {
      final tooltip = await run(tester, holder: _Holder.flutter, act: act);
      final app = await run(tester, holder: _Holder.app, act: act);
      final face = await run(tester, holder: _Holder.face, act: act);
      expect(app, tooltip, reason: 'an AppTooltip');
      expect(face, tooltip, reason: 'an icon button');
      expect(
        tooltip.any((frame) => frame.contains(RegExp(r'0\.[0-9]*[1-9]'))),
        isTrue,
        reason: 'the case caught a window part way through a fade: $tooltip',
      );
    });
  }
}

/// What holds the two targets' tooltips.
enum _Holder { flutter, app, face }

class _Scene {
  _Scene(this.tester);

  final WidgetTester tester;
  TestGesture? mouse;
  final read = <String>[];

  Offset at(String key) => tester.getCenter(find.byKey(ValueKey<String>(key)));

  Future<void> hover(String key, {bool settle = true}) async {
    final pointer = mouse ??= await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    if (read.isEmpty && settle) {
      await pointer.addPointer(location: at('elsewhere'));
    }
    await pointer.moveTo(at(key));
    await tester.pump();
    if (settle) {
      await tester.pump(const Duration(milliseconds: 300));
      read.add('over $key: ${_shown()}');
    }
  }

  /// The windows on screen, frame by frame: at once, then 16, 56 and 156ms
  /// on — or on to 400ms when [longer].
  Future<void> frames({bool longer = false, int? only}) async {
    final steps = [0, 16, 40, 100, if (longer) ...[50, 100, 100]];
    var at = 0;
    for (final step in steps.take(only ?? steps.length)) {
      await tester.pump(Duration(milliseconds: step));
      at += step;
      read.add('+$at ${_shown()}');
    }
  }

  String _shown() => [
    for (final name in const ['a', 'b'])
      '$name ${_opacityOf(name)?.toStringAsFixed(3) ?? '-'}',
  ].join(' ');

  double? _opacityOf(String text) {
    final found = find.text(text);
    if (found.evaluate().isEmpty) {
      return null;
    }
    final fade = find.ancestor(of: found, matching: find.byType(FadeTransition));
    return tester.widget<FadeTransition>(fade.first).opacity.value;
  }
}
