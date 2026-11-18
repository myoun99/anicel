import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/native/lost_screen.dart';
import 'package:anicel/src/ui/lost_screen_frames.dart';

/// Counts the frames that are DRAWN: `drawFrame` as it stands UNDER the
/// law — a frame the law lets pass never gets here.
class _CountsDrawnFrames extends AutomatedTestWidgetsFlutterBinding {
  int drawnFrames = 0;

  @override
  void drawFrame() {
    drawnFrames += 1;
    super.drawFrame();
  }
}

/// The test binding with the PRODUCTION law mixed in, as the app's binding
/// wears it — `flutter_test`'s own draws every frame it begins, and the law
/// could go with every test green under it.
class _LostScreenTestBinding extends _CountsDrawnFrames with LostScreenFrames {}

/// 🔬On the Surface (Intel, 2026-11-18 15:08) the first frame drawn after the
/// screen's device was reset ended the process in Impeller's GLES encoder —
/// a FML_CHECK nothing in Dart catches (a-lost-gpu-leaves-the-window-
/// unpainted). So once the device went, a frame is begun as ever and drawn
/// no more ([LostScreenFrames]): what waits for a frame hears it, and
/// nothing reaches the screen.
void main() {
  final binding = _LostScreenTestBinding();

  tearDown(LostScreen.debugForget);

  testWidgets('once the screen went a frame is begun — its callbacks are '
      'called — and is not drawn; before, each is drawn', (tester) async {
    final shown = ValueNotifier(0);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder<int>(
          valueListenable: shown,
          builder: (context, value, _) => Text('$value'),
        ),
      ),
    );
    final before = binding.drawnFrames;
    shown.value = 1;
    await tester.pump();
    expect(binding.drawnFrames, before + 1, reason: '⛔premise: drawn');

    LostScreen.debugGo();
    var called = 0;
    binding.addPostFrameCallback((_) => called += 1);
    shown.value = 2;
    await tester.pump();
    await tester.pump();
    expect(binding.drawnFrames, before + 1);
    expect(called, 1, reason: 'the frame is begun as ever');
    expect(find.text('1'), findsOneWidget, reason: 'nothing built anew');
  });
}
