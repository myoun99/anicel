import 'package:anicel/src/native/qa_tablet_bridge.dart';

/// A tablet bridge a test plays the driver's side of: always there, opening
/// as asked and noting the window it was asked to open with, its queue
/// saying [gap] and [overflowed] (WintabPenService.debugBridge).
class FakeTabletBridge implements QaTabletBridge {
  /// The window the context was opened with; null before it was.
  Duration? within;

  int? gap = 7;

  int overflowedCount = 3;

  bool closed = false;

  @override
  bool get available => true;

  @override
  bool open({required Duration within}) {
    this.within = within;
    return true;
  }

  @override
  List<QaTabletPacket> poll() => const [];

  @override
  int overflowed() => overflowedCount;

  @override
  int? clockGap() => gap;

  @override
  void close() => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
