import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A DRAG FROM THE OS, as the drop plugin hears it — through its channel:
/// entered, moved, let go — so the window's own drop target decides where
/// the point is and hands the paths on. A test that called a handler would
/// survive the target losing its callback.
///
/// ⚠️Windows and Android hand the point over in DEVICE pixels, so a test
/// gives its view one device pixel to a logical one
/// (`tester.view.devicePixelRatio = 1`) and the point means the same on
/// every platform.
Future<void> osDragOver(WidgetTester tester, Offset at) async {
  await _hear(tester, 'entered', <double>[at.dx, at.dy]);
  await osDragMovesTo(tester, at);
}

/// The drag from the OS, already over the window, moved on to [at].
Future<void> osDragMovesTo(WidgetTester tester, Offset at) async {
  await _hear(tester, 'updated', <double>[at.dx, at.dy]);
  await tester.pump();
}

/// [paths] dragged from the OS to [at] and let go there ([osDragOver]).
Future<void> osDrop(
  WidgetTester tester,
  List<String> paths, {
  required Offset at,
}) async {
  await osDragOver(tester, at);
  await _hear(tester, 'performOperation', paths);
  await tester.pump();
  await tester.pump();
}

/// The drag from the OS left the window without being let go.
Future<void> osDragLeaves(WidgetTester tester) async {
  await _hear(tester, 'exited', null);
  await tester.pump();
}

Future<void> _hear(WidgetTester tester, String method, Object? arguments) =>
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'desktop_drop',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      (_) {},
    );
