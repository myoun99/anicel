import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_span_layout.dart';

/// R28 #4, the LAYOUT arm: the two frame-axis render objects — the axis
/// box that sizes a row and the span layout that places a sparse row's
/// children — are subscribed to the LIVE geometry handle for their
/// lifetime. A zoom step changes the handle's value and they re-lay
/// themselves out with no widget rebuilding; swapping the handle moves the
/// subscription with it, so the old handle can no longer move them and the
/// new one does.
/// A handle that counts its listeners, so a swap can be seen to let the
/// old handle go — a stale subscription changes nothing on screen (layout
/// reads the current handle), it only leaks a listener per swap.
class _CountingHandle extends ValueNotifier<TimelineFrameGeometry> {
  _CountingHandle(super.value);

  int listeners = 0;

  @override
  void addListener(VoidCallback listener) {
    listeners += 1;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners -= 1;
    super.removeListener(listener);
  }
}

void main() {
  TimelineFrameGeometry geometryOf(double cellExtent) => TimelineFrameGeometry(
    frameCellExtent: cellExtent,
    frameStartIndex: 0,
    frameEndIndexExclusive: 10,
  );

  Future<void> pumpAxisBox(
    WidgetTester tester,
    TimelineFrameGeometryHandle handle,
  ) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: TimelineFrameAxisBox(
          geometry: handle,
          crossAxisExtent: 20,
          axis: Axis.horizontal,
          child: const SizedBox(key: ValueKey('child')),
        ),
      ),
    ),
  );

  Future<void> pumpSpanLayout(
    WidgetTester tester,
    TimelineFrameGeometryHandle handle,
  ) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          height: 20,
          child: TimelineFrameSpanLayout(
            geometry: handle,
            crossAxisExtent: 20,
            axis: Axis.horizontal,
            children: const [
              TimelineFrameSpan(
                placement: TimelineFrameSpanPlacement(
                  startIndex: 2,
                  endIndexExclusive: 4,
                ),
                child: SizedBox(key: ValueKey('span')),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  testWidgets('the axis box follows its handle, and only its CURRENT one', (
    tester,
  ) async {
    final first = _CountingHandle(geometryOf(10));
    final second = _CountingHandle(geometryOf(10));
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final child = find.byKey(const ValueKey('child'));

    await pumpAxisBox(tester, first);
    expect(tester.getSize(child).width, 100);
    expect(first.listeners, 1);

    // A zoom step through the live handle — no rebuild, a new layout.
    first.value = geometryOf(20);
    await tester.pump();
    expect(tester.getSize(child).width, 200);

    // The handle swaps: the old one is let go of, the new one is listened to.
    await pumpAxisBox(tester, second);
    expect(tester.getSize(child).width, 100);
    expect(first.listeners, 0, reason: 'the old handle is let go of');
    expect(second.listeners, 1);
    first.value = geometryOf(30);
    await tester.pump();
    expect(tester.getSize(child).width, 100, reason: 'the old handle is mute');
    second.value = geometryOf(15);
    await tester.pump();
    expect(tester.getSize(child).width, 150);
  });

  testWidgets('the span layout follows its handle, and only its CURRENT one', (
    tester,
  ) async {
    final first = _CountingHandle(geometryOf(10));
    final second = _CountingHandle(geometryOf(10));
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final span = find.byKey(const ValueKey('span'));

    await pumpSpanLayout(tester, first);
    expect(tester.getTopLeft(span).dx, 20);
    expect(tester.getSize(span).width, 20);
    expect(first.listeners, 1);

    first.value = geometryOf(20);
    await tester.pump();
    expect(tester.getTopLeft(span).dx, 40);
    expect(tester.getSize(span).width, 40);

    await pumpSpanLayout(tester, second);
    expect(tester.getTopLeft(span).dx, 20);
    expect(first.listeners, 0, reason: 'the old handle is let go of');
    expect(second.listeners, 1);
    first.value = geometryOf(30);
    await tester.pump();
    expect(tester.getTopLeft(span).dx, 20, reason: 'the old handle is mute');
    second.value = geometryOf(15);
    await tester.pump();
    expect(tester.getTopLeft(span).dx, 30);
    expect(tester.getSize(span).width, 30);
  });
}
