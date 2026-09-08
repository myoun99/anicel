import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/playback/playback_transport.dart';
import '../../helpers/fake_playback_transport.dart';

/// 🚨★★★ [PlaybackTransports] is the ONE answer to 「누가 재생 중인가」.
///
/// The gate's own tests drive it through real pointers and keys; these are
/// the parts a widget test cannot reach — registration that survives being
/// repeated, and a disposal that actually lets go.
void main() {
  late FakePlaybackTransport canvas;
  late FakePlaybackTransport viewer;
  late PlaybackTransports transports;
  late int notifications;

  setUp(() {
    canvas = FakePlaybackTransport();
    viewer = FakePlaybackTransport();
    transports = PlaybackTransports();
    notifications = 0;
    transports.addListener(() => notifications += 1);
  });

  tearDown(() {
    transports.dispose();
    canvas.dispose();
    viewer.dispose();
  });

  test('ANY member playing is the answer, and it follows them', () {
    transports
      ..add(canvas)
      ..add(viewer);
    expect(transports.value, isFalse);

    viewer.play();
    expect(transports.value, isTrue, reason: 'the viewer counts as playing');

    viewer.stop();
    expect(transports.value, isFalse);
  });

  test('a flip notifies, so the gate arms without polling', () {
    transports.add(canvas);
    final atRest = notifications;

    canvas.play();

    expect(notifications, greaterThan(atRest));
  });

  test('stopAll stops every member — asking WHICH is playing and then '
      'stopping it would read a changing thing twice', () {
    transports
      ..add(canvas)
      ..add(viewer);
    canvas.play();
    viewer.play();

    transports.stopAll();

    expect(canvas.isPlaying, isFalse);
    expect(viewer.isPlaying, isFalse);
  });

  /// ⛔A State that re-registers (hot reload, a rebind) must not end up in
  /// the list twice: one removal would then leave a listener behind and a
  /// closed viewer would keep arming the gate.
  test('registering twice registers once — one remove really removes', () {
    transports
      ..add(canvas)
      ..add(canvas);

    transports.remove(canvas);
    canvas.play();

    expect(
      transports.value,
      isFalse,
      reason: 'a removed transport is not part of the answer',
    );
    transports.stopAll();
    expect(canvas.stops, 0, reason: 'nor is it stopped any more');
  });

  test('disposing lets go of its members — a flip afterwards is nobody\'s '
      'business', () {
    transports.add(canvas);
    transports.dispose();

    expect(canvas.play, returnsNormally);

    // The tearDown's dispose would be the second one.
    transports = PlaybackTransports();
  });
}
