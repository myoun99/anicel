import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/se_line_type.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/se_name_tag_plan.dart';
import 'package:anicel/src/ui/text/se_name_tag_paint.dart';

/// 🗣️I-20 (유저 2026-09-30): 「해당 타입의 텍스트는 네임태그로서 화면에
/// 보이게함. 위치는 캐릭터 이름 박스 위 중앙정렬」 — and every type shows on
/// the canvas, ON included (「ON일때는 … 캔버스에는 표시」).
void main() {
  const canvas = CanvasSize(width: 2340, height: 1654);
  const camera = CanvasSize(width: 1920, height: 1080);

  ResolvedSeNameTag tagFor(SeLineType type, {String? seName = 'タモツ'}) {
    const frameId = FrameId('s-cel');
    final row = Layer(
      id: const LayerId('s'),
      name: 'SE',
      kind: LayerKind.se,
      frames: [
        Frame(
          id: frameId,
          duration: 12,
          strokes: const [],
          name: 'おはよう',
          seName: seName,
          seType: type,
        ),
      ],
      timeline: {0: const TimelineExposure.drawing(frameId, length: 12)},
    );
    return resolveSeNameTagsAt(
      trackSeLayers: [row],
      cutStartFrame: 0,
      localFrameIndex: 3,
      canvas: canvas,
      cameraFrame: camera,
    ).single;
  }

  test('every delivery shows on the canvas, in the name\'s own style', () {
    for (final type in SeLineType.values) {
      final tag = tagFor(type);
      expect(tag.delivery?.text, type.label, reason: type.name);
      expect(tag.delivery?.style, tag.content.style, reason: '「네임태그로서」');
    }
  });

  test('it sits OVER the name box, centred on it', () {
    final tag = tagFor(SeLineType.mono);
    final box = seNameTagBoxBounds(tag, canvasSize: canvas);
    final over = seNameTagDeliveryBounds(tag, canvasSize: canvas)!;
    expect(over.bottom, lessThan(box.top), reason: 'above, not across');
    expect(over.center.dx, closeTo(box.center.dx, 0.5));
  });

  test('a new delivery is a new picture — the repaint signature sees it', () {
    expect(
      seNameTagSignature([tagFor(SeLineType.on)]),
      isNot(seNameTagSignature([tagFor(SeLineType.off)])),
    );
  });
}
