import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/cel_pixel_overwrite.dart'
    show CelPixelVerb;
import 'package:anicel/src/ui/session/pixel_verb_preview.dart';

/// 🗣️I-164 (유저 2026-11-05): 「프리뷰는 한번에 하나만 활성화 가능하고, 그
/// 색 편집 앵커창 나가면 사라짐」 — the preview's own state, apart from the
/// list that turns it and the canvas that draws it.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  const cel = BrushFrameKey(
    projectId: ProjectId('project'),
    trackId: TrackId('track'),
    cutId: CutId('cut'),
    layerId: LayerId('layer'),
    frameId: FrameId('frame'),
  );

  ({
    PixelVerbPreview preview,
    List<CelPixelVerb> made,
    ChangeNotifier inputs,
    BrushFrameStore store,
  })
  build() {
    final store = BrushFrameStore();
    final coordinator = BrushFrameEditingCoordinator(
      initialFrameKey: cel,
      frameStore: store,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: 4,
      ),
      historyPolicy: const BrushHistoryPolicy(retainedSessionLimit: 4),
    );
    final made = <CelPixelVerb>[];
    final inputs = ChangeNotifier();
    addTearDown(inputs.dispose);
    final preview = PixelVerbPreview(
      previewOf: (verb) {
        made.add(verb);
        return {cel: BitmapSurface(canvasSize: canvasSize, tileSize: 4)};
      },
      inputs: inputs,
      coordinator: () => coordinator,
    );
    addTearDown(preview.dispose);
    return (preview: preview, made: made, inputs: inputs, store: store);
  }

  test('off, it shows nothing and makes nothing', () {
    final (:preview, :made, inputs: _, :store) = build();
    expect(preview.cels(), isEmpty);
    expect(made, isEmpty);
    expect(store.reclaimableViewCount, 0);
  });

  test('on, the pictures are made once when asked and kept until what they '
      'are made of moves — a knob, the history', () {
    final (:preview, :made, :inputs, store: _) = build();
    var told = 0;
    preview.addListener(() => told += 1);

    preview.verb = CelPixelVerb.binarize;
    expect(told, 1, reason: 'the canvas hears it turn on');
    expect(made, isEmpty, reason: 'made when the canvas asks');
    final first = preview.cels();
    expect(preview.cels(), same(first), reason: 'kept: a paint asks again');
    expect(made, [CelPixelVerb.binarize]);

    inputs.notifyListeners();
    expect(told, 2, reason: 'drawn again as the knob turns');
    expect(preview.cels(), isNot(same(first)));
    expect(made, [CelPixelVerb.binarize, CelPixelVerb.binarize]);
  });

  test('one row at a time: turning another on is the first one off', () {
    final (:preview, :made, inputs: _, store: _) = build();
    preview.verb = CelPixelVerb.binarize;
    preview.cels();
    preview.verb = CelPixelVerb.keepColour;
    preview.cels();
    expect(preview.verb, CelPixelVerb.keepColour);
    expect(made, [CelPixelVerb.binarize, CelPixelVerb.keepColour]);
  });

  test('its pictures are a view the store may take back, made again when '
      'asked — and let go when it turns off', () {
    final (:preview, :made, inputs: _, :store) = build();
    preview.verb = CelPixelVerb.deleteColour;
    final first = preview.cels();
    expect(store.reclaimableViewCount, 1);

    store.respondToMemoryPressure();
    expect(preview.cels(), isNot(same(first)), reason: 'made again');
    expect(made, hasLength(2));

    preview.verb = null;
    expect(preview.cels(), isEmpty);
    expect(store.reclaimableViewCount, 0);
  });

  test('a knob turning while it is off tells nobody', () {
    final (:preview, made: _, :inputs, store: _) = build();
    var told = 0;
    preview.addListener(() => told += 1);
    inputs.notifyListeners();
    expect(told, 0);
  });
}
