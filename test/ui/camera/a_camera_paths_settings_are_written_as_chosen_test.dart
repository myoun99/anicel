import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_path_settings.dart';
import 'package:anicel/src/ui/camera/camera_path_settings_rows.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';
import '../../helpers/number_pad_keyboard.dart';

/// I-89 ④ — how the canvas shows a camera's path, as rows of a list
/// ([cameraPathSettingsRows]): what is chosen there is written whole, the
/// chosen one is the one tinted, and a count of frames reads in frames and
/// is one at least (유저 2026-10-10: 「점은 1f2f3f 정하는게아니라 커스텀으로
/// … 6f든 뭐든」).
///
/// The list opens from the camera row's path button (④-Q1, 유저 2026-10-12:
/// 「카메라 경로표시 설정은 카메라 레이어에 두고싶어. 거기에 버튼으로서」);
/// here the rows open from a trigger of their own.
void main() {
  void reset() =>
      CameraPathSettings.settings.value = const CameraPathSettings();
  setUp(reset);
  tearDown(reset);

  /// Opens the rows. What they write lands in the list returned, and on the
  /// live value, as the app's settings write it.
  Future<List<CameraPathSettings>> open(WidgetTester tester) async {
    final written = <CameraPathSettings>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PanelFlyoutTrigger(
              key: const ValueKey<String>('open'),
              entriesBuilder: () => cameraPathSettingsRows((settings) {
                written.add(settings);
                CameraPathSettings.settings.value = settings;
              }),
              child: const Icon(Icons.tune),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('open')));
    await tester.pumpAndSettle();
    return written;
  }

  /// The pill tinted in the row [row].
  String chosenIn(WidgetTester tester, String row) => tester
      .widget<PillStrip>(
        find.descendant(
          of: find.byKey(ValueKey<String>(row)),
          matching: find.byType(PillStrip),
        ),
      )
      .items
      .singleWhere((item) => item.selected)
      .keyValue;

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pump();
  }

  testWidgets('what is chosen is written whole, and is the one tinted', (
    tester,
  ) async {
    final written = await open(tester);
    expect(
      chosenIn(tester, 'camera-path-show'),
      'camera-path-show-spaceAndTime',
    );
    expect(chosenIn(tester, 'camera-path-range'), 'camera-path-range-allKeys');

    await tap(tester, 'camera-path-show-space');
    await tap(tester, 'camera-path-range-aroundPlayhead');
    expect(written, const [
      CameraPathSettings(show: CameraPathShow.space),
      CameraPathSettings(
        show: CameraPathShow.space,
        range: CameraPathRange.aroundPlayhead,
      ),
    ]);
    expect(chosenIn(tester, 'camera-path-show'), 'camera-path-show-space');
    expect(
      chosenIn(tester, 'camera-path-range'),
      'camera-path-range-aroundPlayhead',
    );
  });

  testWidgets('a count of frames reads in frames, steps by one, takes what '
      'is typed — and is one at least', (tester) async {
    await open(tester);
    Finder readout(String row, String text) => find.descendant(
      of: find.byKey(ValueKey<String>('$row-row')),
      matching: find.text(text),
    );
    expect(readout('camera-path-tick-every', '1f'), findsOneWidget);
    expect(readout('camera-path-around', '12f'), findsOneWidget);

    await tap(tester, 'camera-path-tick-every-step-up');
    await tap(tester, 'camera-path-around-step-down');
    expect(
      CameraPathSettings.settings.value,
      const CameraPathSettings(tickEvery: 2, around: 11),
    );
    expect(readout('camera-path-tick-every', '2f'), findsOneWidget);
    expect(readout('camera-path-around', '11f'), findsOneWidget);

    Future<void> type(String row, String text) async {
      await tap(tester, '$row-edit');
      await openThePadsKeyboard(tester);
      await tester.enterText(find.byKey(ValueKey<String>('$row-input')), text);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }

    await type('camera-path-tick-every', '6');
    expect(CameraPathSettings.settings.value.tickEvery, 6);
    await type('camera-path-around', '0');
    expect(CameraPathSettings.settings.value.around, 1);

    await type('camera-path-tick-every', '1');
    await tap(tester, 'camera-path-tick-every-step-down');
    expect(CameraPathSettings.settings.value.tickEvery, 1);
  });

  testWidgets('a list left open writes from the value as it is at the '
      'press, never the one it opened on', (tester) async {
    final written = await open(tester);
    CameraPathSettings.settings.value = const CameraPathSettings(
      range: CameraPathRange.aroundPlayhead,
    );
    await tester.pump();
    await tap(tester, 'camera-path-show-off');
    expect(
      written.single,
      const CameraPathSettings(
        show: CameraPathShow.off,
        range: CameraPathRange.aroundPlayhead,
      ),
    );
  });
}
