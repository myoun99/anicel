import 'package:anicel/src/native/qa_tablet_bridge.dart';

/// A tablet bridge a test plays the driver's side of: always there, opening
/// as asked — after the [refusals] it is given — and noting the window it
/// was asked to open with, its queue saying [gap] and [overflowed]
/// (WintabPenService.debugBridge).
class FakeTabletBridge implements QaTabletBridge {
  /// The window the context was opened with; null before it was.
  Duration? within;

  /// What the next opens answer, the first first, before one opens.
  final List<QaTabletOpen> refusals = [];

  /// What the next poll hands over.
  final List<QaTabletPacket> queued = [];

  /// Whether a driver answers.
  bool driver = true;

  int? gap = 7;

  int overflowedCount = 3;

  bool closed = false;

  @override
  bool get available => driver;

  @override
  QaTabletOpen open({required Duration within}) {
    if (refusals.isNotEmpty) {
      return refusals.removeAt(0);
    }
    this.within = within;
    return QaTabletOpen.opened;
  }

  @override
  List<QaTabletPacket> poll() {
    final handed = [...queued];
    queued.clear();
    return handed;
  }

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
