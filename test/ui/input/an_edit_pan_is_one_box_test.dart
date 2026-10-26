// Card frame-panels-build-in-one-frame (2026-10-25): the timeline's edit
// pan — the cells' and the lanes' range drag, a header graph's box, a rail
// row's move or select — is ONE box ([TimelineEditPan]) that hears the
// one-finger mode itself. It was a `FingerModeDevices` around a
// `RawGestureDetector` of one eager pan; these hold the box to that
// composition, gesture for gesture, and pin what only the box can be told.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/ui/input/eager_pan_gesture_recognizer.dart';
import 'package:anicel/src/ui/input/timeline_edit_pan.dart';

const _pan = ValueKey<String>('pan');

/// What a pan heard, in order.
typedef _Heard = List<String>;

/// The hooks a pan reports through, writing into [heard].
({
  GestureDragStartCallback onStart,
  GestureDragUpdateCallback onUpdate,
  VoidCallback onEnd,
  VoidCallback onCancel,
})
_hooks(_Heard heard) => (
  onStart: (details) => heard.add(
    'start ${details.localPosition} ${details.globalPosition}',
  ),
  onUpdate: (details) => heard.add('update ${details.delta}'),
  onEnd: () => heard.add('end'),
  onCancel: () => heard.add('cancel'),
);

/// The pan as it was built — a detector built again whenever the input
/// settings move (the `FingerModeDevices` constructor it went through is
/// gone with its last user, F-475).
Widget _asItWas(
  _Heard heard, {
  bool Function(Offset down, Offset now)? firstStepAt,
  Widget? child,
}) {
  final hooks = _hooks(heard);
  return ValueListenableBuilder<AppInputSettings>(
    key: _pan,
    valueListenable: AppInput.settings,
    builder: (context, settings, child) => RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        EagerPanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerPanGestureRecognizer>(
              () => EagerPanGestureRecognizer(debugOwner: heard),
              (recognizer) {
                recognizer.firstStepAt = firstStepAt;
                recognizer.supportedDevices = AppInput.timelineEditPanDevices;
                recognizer.gestureSettings =
                    MediaQuery.maybeGestureSettingsOf(context);
                recognizer.dragStartBehavior = DragStartBehavior.down;
                recognizer.onStart = hooks.onStart;
                recognizer.onUpdate = hooks.onUpdate;
                recognizer.onEnd = (_) => hooks.onEnd();
                recognizer.onCancel = hooks.onCancel;
              },
            ),
      },
      child: child,
    ),
    child: child,
  );
}

/// The pan as one box.
Widget _box(
  _Heard heard, {
  bool Function(Offset down, Offset now)? firstStepAt,
  Widget? child,
}) {
  final hooks = _hooks(heard);
  return TimelineEditPan(
    key: _pan,
    debugOwner: heard,
    firstStepAt: firstStepAt,
    onStart: hooks.onStart,
    onUpdate: hooks.onUpdate,
    onEnd: hooks.onEnd,
    onCancel: hooks.onCancel,
    child: child,
  );
}

/// [pan] in a loose room of its own, as a timeline holds it: a tap under it
/// and a vertical scroll around it, each writing into [under] what it won,
/// with [settings] as the device gesture settings.
Widget _hosted(
  Widget pan, {
  required List<String> under,
  DeviceGestureSettings settings = const DeviceGestureSettings(touchSlop: 18),
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(gestureSettings: settings),
    child: Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => under.add('scroll'),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => under.add('tap'),
            child: SizedBox(
              width: 200,
              height: 60,
              child: Center(child: pan),
            ),
          ),
        ),
      ),
    ),
  ),
);

/// One finger moves the view — so the timeline's edit pans leave it.
final _navigating = AppInputSettings.testCorpusBaseline.copyWith(
  touchDragOneFinger: CanvasTouchDragAction.navigate,
);

/// One finger draws — so the edit pans take it.
final _drawing = AppInputSettings.testCorpusBaseline.copyWith(
  touchDragOneFinger: CanvasTouchDragAction.draw,
);

typedef _Reading = ({_Heard heard, List<String> under, Size size});

void main() {
  late AppInputSettings kept;
  setUp(() => kept = AppInput.settings.value);
  tearDown(() => AppInput.settings.value = kept);

  Future<void> drag(
    WidgetTester tester,
    PointerDeviceKind kind,
    List<Offset> steps,
  ) async {
    final at = tester.getCenter(find.byKey(_pan));
    final gesture = await tester.startGesture(at, kind: kind);
    for (final step in steps) {
      await gesture.moveBy(step);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
  }

  Future<_Reading> read(
    WidgetTester tester,
    Widget Function(_Heard heard) pan, {
    required PointerDeviceKind kind,
    required List<Offset> steps,
    DeviceGestureSettings settings = const DeviceGestureSettings(
      touchSlop: 18,
    ),
  }) async {
    final heard = <String>[];
    final under = <String>[];
    await tester.pumpWidget(
      _hosted(pan(heard), under: under, settings: settings),
    );
    await drag(tester, kind, steps);
    final reading = (
      heard: heard,
      under: under,
      size: tester.getSize(find.byKey(_pan)),
    );
    await tester.pumpWidget(const SizedBox());
    return reading;
  }

  final drags = <String, List<Offset>>{
    'a drag': const [Offset(4, 1), Offset(30, 2), Offset(-10, 0)],
    'a press that hardly moves': const [Offset(1, 0)],
    'a long drag across': const [Offset(0, 25), Offset(0, 25)],
  };
  final childOf = <String, Widget? Function()>{
    'with no child': () => null,
    'around a child': () => const SizedBox(width: 40, height: 20),
  };

  for (final MapEntry(key: settingName, value: setting) in {
    'one finger moving the view': _navigating,
    'one finger drawing': _drawing,
  }.entries) {
    for (final kind in [
      PointerDeviceKind.mouse,
      PointerDeviceKind.touch,
      PointerDeviceKind.stylus,
    ]) {
      for (final MapEntry(key: dragName, value: steps) in drags.entries) {
        for (final MapEntry(key: childName, value: child) in childOf.entries) {
          testWidgets('$dragName by ${kind.name}, $childName, with '
              '$settingName, is heard as the detector it replaced heard it', (
            tester,
          ) async {
            AppInput.settings.value = setting;
            final now = await read(
              tester,
              (heard) => _box(heard, child: child()),
              kind: kind,
              steps: steps,
            );
            final old = await read(
              tester,
              (heard) => _asItWas(heard, child: child()),
              kind: kind,
              steps: steps,
            );
            expect(now.heard, old.heard);
            expect(now.under, old.under);
            expect(now.size, old.size);
          });
        }
      }
    }
  }

  testWidgets('a first step the host names starts the drag as the detector '
      'it replaced started it', (tester) async {
    AppInput.settings.value = _drawing;
    bool firstStepAt(Offset down, Offset now) => (now - down).distance > 2;
    const steps = [Offset(3, 0), Offset(3, 0)];
    final now = await read(
      tester,
      (heard) => _box(heard, firstStepAt: firstStepAt),
      kind: PointerDeviceKind.touch,
      steps: steps,
    );
    final old = await read(
      tester,
      (heard) => _asItWas(heard, firstStepAt: firstStepAt),
      kind: PointerDeviceKind.touch,
      steps: steps,
    );
    expect(now.heard, old.heard);
    expect(now.heard, contains(startsWith('start')), reason: 'LIVENESS');
  });

  testWidgets('the device gesture settings are the context\'s, as the '
      'detector it replaced was handed them', (tester) async {
    AppInput.settings.value = _drawing;
    const wide = DeviceGestureSettings(touchSlop: 40);
    const steps = [Offset(25, 0)];
    final now = await read(
      tester,
      _box,
      kind: PointerDeviceKind.touch,
      steps: steps,
      settings: wide,
    );
    final old = await read(
      tester,
      _asItWas,
      kind: PointerDeviceKind.touch,
      steps: steps,
      settings: wide,
    );
    expect(now.heard, old.heard);
    final narrow = await read(
      tester,
      _box,
      kind: PointerDeviceKind.touch,
      steps: steps,
    );
    expect(narrow.heard, isNot(now.heard), reason: 'CONTROL — the slop counts');
  });

  testWidgets('new device gesture settings reach the box it is mounted in', (
    tester,
  ) async {
    AppInput.settings.value = _drawing;
    final heard = <String>[];
    const steps = [Offset(25, 0)];
    await tester.pumpWidget(
      _hosted(
        _box(heard),
        under: [],
        settings: const DeviceGestureSettings(touchSlop: 40),
      ),
    );
    await drag(tester, PointerDeviceKind.touch, steps);
    expect(heard, isNot(contains(startsWith('start'))), reason: 'the slop');

    await tester.pumpWidget(_hosted(_box(heard), under: []));
    await drag(tester, PointerDeviceKind.touch, steps);
    expect(heard, contains(startsWith('start')));
  });

  testWidgets('a new one-finger mode reaches the box it is mounted in — a '
      'finger it left starts a drag once the mode takes it', (tester) async {
    AppInput.settings.value = _navigating;
    final heard = <String>[];
    await tester.pumpWidget(_hosted(_box(heard), under: []));
    await drag(tester, PointerDeviceKind.touch, drags['a drag']!);
    expect(heard, isEmpty, reason: 'a finger moves the view');

    AppInput.settings.value = _drawing;
    await drag(tester, PointerDeviceKind.touch, drags['a drag']!);
    expect(heard, contains(startsWith('start')), reason: 'a finger edits');

    AppInput.settings.value = _navigating;
    heard.clear();
    await drag(tester, PointerDeviceKind.touch, drags['a drag']!);
    expect(heard, isEmpty, reason: 'and leaves it again');
  });

  testWidgets('the box is one element, and stops hearing the mode once it '
      'is gone', (tester) async {
    // ignore: invalid_use_of_protected_member
    bool heardBy() => AppInput.settings.hasListeners;
    expect(heardBy(), isFalse, reason: 'nothing else hears it here');

    await tester.pumpWidget(_hosted(_box(<String>[]), under: []));
    var children = 0;
    tester.element(find.byKey(_pan)).visitChildren((_) => children += 1);
    expect(children, 0);
    expect(heardBy(), isTrue);

    await tester.pumpWidget(const SizedBox());
    expect(heardBy(), isFalse);
  });
}
