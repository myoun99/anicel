import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/media/media_asset_drag_data.dart';
import 'package:anicel/src/ui/media/media_asset_drop_target.dart';

const _sourceKey = ValueKey<String>('drag-source');
const _otherSourceKey = ValueKey<String>('drag-source-other');
const _targetKey = ValueKey<String>('drop-target');
const _underKey = ValueKey<String>('under-the-target');

/// THE place entrance, on its own: it reports a file and a point, and it
/// leaves the surface underneath alone until a matching drag is in flight.
///
/// The hosts that use it (a timeline layer row, the stage) both lie over
/// something that must keep its pointers — a cell tap, a brush stroke — so
/// the second half matters as much as the first.
Future<void> _pump(
  WidgetTester tester, {
  required void Function(String path, Offset globalPosition) onDrop,
  required VoidCallback onTapUnder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Row(
              children: [
                Draggable<MediaAssetDragData>(
                  data: const MediaAssetDragData(
                    path: 'C:/art/BG_a12.png',
                    name: 'BG_a12.png',
                  ),
                  // What the media browser's row does, and what makes the
                  // reported point the pointer rather than the pointer minus
                  // wherever inside the row the grab happened.
                  dragAnchorStrategy: pointerDragAnchorStrategy,
                  feedback: const SizedBox(width: 8, height: 8),
                  child: Container(
                    key: _sourceKey,
                    width: 40,
                    height: 40,
                    color: const Color(0xFF888888),
                  ),
                ),
                // A panel-tab drag, a layer drag: another payload entirely.
                Draggable<String>(
                  data: 'panel-tab',
                  feedback: const SizedBox(width: 8, height: 8),
                  child: Container(
                    key: _otherSourceKey,
                    width: 40,
                    height: 40,
                    color: const Color(0xFF444444),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    key: _underKey,
                    onTap: onTapUnder,
                    child: const ColoredBox(color: Color(0xFF222222)),
                  ),
                  Positioned.fill(
                    child: MediaAssetDropTarget(
                      key: _targetKey,
                      onDrop: onDrop,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a drop reports the file and the point it landed on', (
    tester,
  ) async {
    String? droppedPath;
    Offset? droppedAt;
    await _pump(
      tester,
      onDrop: (path, globalPosition) {
        droppedPath = path;
        droppedAt = globalPosition;
      },
      onTapUnder: () {},
    );

    final dropPoint =
        tester.getRect(find.byKey(_targetKey)).topLeft + const Offset(120, 60);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_sourceKey)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(dropPoint);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(droppedPath, 'C:/art/BG_a12.png');
    // Where the pointer was, not where the target starts — the hosts read a
    // frame out of this.
    expect(droppedAt, dropPoint);
  });

  testWidgets('idle, it absorbs no hit test', (tester) async {
    var taps = 0;
    await _pump(tester, onDrop: (_, _) {}, onTapUnder: () => taps += 1);

    // The target covers the whole surface. Tapping through it is what
    // drawing on the stage and tapping a cell depend on.
    await tester.tapAt(tester.getCenter(find.byKey(_targetKey)));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('a drag of something else passes through', (tester) async {
    var dropped = 0;
    await _pump(tester, onDrop: (_, _) => dropped += 1, onTapUnder: () {});

    // A different payload is not this entrance's business, and the target
    // must not eat it.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_otherSourceKey)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getCenter(find.byKey(_targetKey)));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(dropped, 0);
  });
}
