import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/key_clipboard.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId;
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart'
    show seNameTagSizeLaneId;
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane, transformLaneDisplayOrder;

/// 🗣️F-388 (유저 2026-10-17): 「키도 복붙기능 제대로 만들고 기존것들이랑 법
/// 통일하고」 — and F-388-Q1 (10-20): 「프레임과 똑같이 끼워 넣기 — 그냥
/// 생각할것도없이 프레임블록 복붙이랑 똑같은 규칙」.
///
/// Keys in hand go down where the press stands as a frame copy's run does:
/// standing, in at the playhead, every key from there on moved back by the
/// copy's length; over a selection, the selection replaced and what follows
/// it moved by the difference. 독립 붙여넣기 puts each key down unnamed.
///
/// The collaborator the paste lives in — named so `tool/mutation_run.dart`
/// runs this file for it.
KeyClipboard keyClipboardOf(EditorSessionManager session) =>
    session.keyClipboard;

void main() {
  late EditorSessionManager s;
  late Layer before;
  late ToolbarPanelContext pill;

  setUp(() {
    s = EditorSessionManager(initialProject: createDefaultProject());
    before = s.requireActiveCut.layers.first;
    s.selectLayer(before.id);
    pill = TimelineToolbarPanelContext(s);
  });
  tearDown(() => s.dispose());

  Layer now() =>
      s.requireActiveCut.layers.firstWhere((layer) => layer.id == before.id);

  void key(String laneId, Map<int, double> values, {String? name}) {
    final track = now().transformTrack;
    var lane = switch (laneId) {
      'rotation' => track.rotation,
      _ => track.opacity,
    };
    for (final MapEntry(key: frame, :value) in values.entries) {
      lane = lane.withKey(frame, value);
      if (name != null) {
        lane = lane.withKeyName(frame, name);
      }
    }
    s.laneVerbs.updateLayerTransformTrack(
      before.id,
      laneId == 'rotation'
          ? track.copyWith(rotation: lane)
          : track.copyWith(opacity: lane),
    );
  }

  Map<int, double> rotation() => {
    for (final MapEntry(key: frame, value: key)
        in now().transformTrack.rotation.keys.entries)
      frame: key.value,
  };

  void standOn(String laneId, {required int at}) {
    s.selectFrameIndex(at);
    s.standOnRow(LaneRowAddress(before.id, laneId));
  }

  void select(String laneId, int start, int endExclusive) {
    standOn(laneId, at: start);
    s.laneRangeSelection.value = TimelineLaneSelection(
      layerId: before.id,
      laneId: laneId,
      startIndex: start,
      endIndexExclusive: endExclusive,
    );
  }

  test('standing, the keys go in at the playhead and every key from there '
      'on moves back by the copy\'s length — the one standing there too', () {
    key('rotation', {3: 10, 7: 20, 12: 30});
    standOn('rotation', at: 7);
    pill.copyFrame();
    expect(s.keyClipboard.holdsKeys, isTrue, reason: '⛔전제');

    standOn('rotation', at: 3);
    expect(pill.canPasteIndependentFrame, isTrue);
    pill.pasteIndependentFrame();

    expect(rotation(), {3: 20, 4: 10, 8: 20, 13: 30});
  });

  test('a header\'s copy goes in on every member — one with no key in it '
      'takes the run too, its keys after moving back', () {
    key('rotation', {3: 10});
    key('opacity', {8: 0.5});
    standOn(transformGroupHeaderLane.laneId, at: 3);
    pill.copyFrame();

    standOn(transformGroupHeaderLane.laneId, at: 5);
    pill.pasteIndependentFrame();

    expect(rotation(), {3: 10, 5: 10});
    expect(now().transformTrack.opacity.keys.keys, [9]);
  });

  test('one lane pasted on a header goes on its own lane alone', () {
    key('rotation', {20: 0.5});
    standOn('rotation', at: 20);
    pill.copyFrame();

    standOn(transformGroupHeaderLane.laneId, at: 30);
    pill.pasteIndependentFrame();

    expect(rotation()[30], 0.5);
    expect(now().transformTrack.opacity.keys, isEmpty);
  });

  test('over a selection, the selection is replaced and what follows it '
      'moves by the difference', () {
    key('rotation', {3: 10, 7: 20, 12: 30, 15: 40});
    select('rotation', 2, 10);
    pill.copyFrame();
    expect(s.keyClipboard.bankedKeyFrames, {
      'rotation': {1, 5},
    }, reason: '⛔전제: eight frames, keys at 1 and 5 of them');

    select('rotation', 11, 14);
    pill.pasteIndependentFrame();

    expect(
      rotation(),
      {3: 10, 7: 20, 12: 10, 16: 20, 20: 40},
      reason: '12 lifted with its frames, 15 moved by 8 − 3',
    );
  });

  test('독립 붙여넣기 puts every key down unnamed — the copied one keeps its '
      'name', () {
    key('rotation', {7: 20}, name: 'A');
    standOn('rotation', at: 7);
    pill.copyFrame();

    standOn('rotation', at: 2);
    pill.pasteIndependentFrame();

    final keys = now().transformTrack.rotation.keys;
    expect(keys[2]?.name, isNull);
    expect(keys[8]?.name, 'A', reason: 'the copied key, moved back by one');
  });

  test('a header\'s copy goes on a header lane by lane, and one lane on a '
      'lane of its kind', () {
    standOn(transformGroupHeaderLane.laneId, at: 4);
    expect(s.cellInstances.createInstancesForSelection(), isTrue);
    pill.copyFrame();

    standOn(transformGroupHeaderLane.laneId, at: 9);
    pill.pasteIndependentFrame();

    final track = now().transformTrack;
    for (final lane in [
      track.anchorPoint,
      track.position,
      track.scale,
      track.rotation,
      track.opacity,
    ]) {
      expect(lane.keys.keys, containsAll([4, 9]));
    }
    expect(transformLaneDisplayOrder, hasLength(5), reason: '⛔전제');

    key('rotation', {20: 50});
    standOn('rotation', at: 20);
    pill.copyFrame();
    standOn('position', at: 30);
    expect(
      pill.canPasteIndependentFrame,
      isFalse,
      reason: 'a number does not go on a position',
    );
    standOn('opacity', at: 30);
    pill.pasteIndependentFrame();
    expect(
      now().transformTrack.opacity.keys[30]?.value,
      0.5,
      reason: '50° shows 50, and 50 on an opacity is 50%',
    );
  });

  // 🗣️key-paste-across-lanes-keeps-the-raw-value-Q1 (유저 2026-10-22): 「회전
  // · 불투명도 · 이펙트의 숫자끼리는 숫자 그대로」 — the number SHOWN. ↩️서피스
  // 실기 (10-23): an opacity's 78.5% went on a rotation as 0.79°, and a
  // rotation's 19.5° on an opacity as 19.5 held, past its 0–1.
  group('a number goes on another lane as its lane shows it', () {
    double? held(String laneId, int frame) => switch (laneId) {
      'rotation' => now().transformTrack.rotation.keys[frame]?.value,
      _ => now().transformTrack.opacity.keys[frame]?.value,
    };

    test('an opacity\'s 78.5% is a rotation\'s 78.5°', () {
      key('opacity', {4: 0.785});
      standOn('opacity', at: 4);
      pill.copyFrame();

      standOn('rotation', at: 9);
      pill.pasteIndependentFrame();

      expect(held('rotation', 9), closeTo(78.5, 1e-9));
    });

    test('a rotation\'s 19.5° is an opacity\'s 19.5%', () {
      key('rotation', {4: 19.5});
      standOn('rotation', at: 4);
      pill.copyFrame();

      standOn('opacity', at: 9);
      pill.pasteIndependentFrame();

      expect(held('opacity', 9), closeTo(0.195, 1e-9));
    });

    test('the linked paste carries the number the same way, its name kept',
        () {
      key('opacity', {4: 0.785}, name: 'A');
      standOn('opacity', at: 4);
      pill.copyFrame();

      standOn('rotation', at: 9);
      expect(pill.canPasteLinkedFrame, isTrue, reason: '⛔전제');
      pill.pasteLinkedFrame();

      final pasted = now().transformTrack.rotation.keys[9];
      expect(pasted?.value, closeTo(78.5, 1e-9));
      expect(pasted?.name, 'A');
    });

    test('a number past where the lane ends is held as its value editor '
        'takes it typed — an opacity at 100%, a blur at 0', () {
      s.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
      final blur = now().effects.single.id;
      double? blurred(int frame) => now()
          .effects
          .single
          .parameters['blurriness']!
          .track
          .keys[frame]
          ?.value;
      key('rotation', {4: 250, 6: -30});
      select('rotation', 4, 7);
      pill.copyFrame();

      select('opacity', 10, 13);
      pill.pasteIndependentFrame();
      select(effectLaneId(blur, 'blurriness'), 10, 13);
      pill.pasteIndependentFrame();

      expect((held('opacity', 10), held('opacity', 12)), (1.0, 0.0));
      expect((blurred(10), blurred(12)), (250, 0));
    });

    test('typed into the value editor, a number is held as a pasted one is '
        '— 78.5 on an opacity is 78.5%, 150% there 100%', () {
      void type(int frame, String value) => s.laneVerbs.setLaneValueAt(
        before.id,
        'opacity',
        frame,
        value,
        frameIsGlobal: false,
        description: 'Type',
        scaleLinked: false,
      );
      type(4, '78.5');
      type(6, '150%');

      expect(held('opacity', 4), closeTo(0.785, 1e-9));
      expect(held('opacity', 6), 1.0);
    });

    test('an opacity\'s 40% is a name tag\'s size of 40', () {
      key('opacity', {4: 0.4});
      standOn('opacity', at: 4);
      pill.copyFrame();

      final se = s.activeTrack.seLayers.first;
      s.selectFrameIndex(9);
      s.standOnRow(LaneRowAddress(se.id, seNameTagSizeLaneId));
      pill.pasteIndependentFrame();

      final size = s.activeTrack.seLayers.first.seNameTag?.track?.fontSize;
      expect(size?.keys[9]?.value, closeTo(40, 1e-9));
    });

    test('a blur\'s number goes on an opacity as the % it shows', () {
      s.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
      final blur = now().effects.single.id;
      s.laneVerbs.setLaneValueAt(
        before.id,
        effectLaneId(blur, 'blurriness'),
        4,
        '40',
        frameIsGlobal: false,
        description: 'Type',
        scaleLinked: false,
      );
      standOn(effectLaneId(blur, 'blurriness'), at: 4);
      pill.copyFrame();

      standOn('opacity', at: 9);
      pill.pasteIndependentFrame();

      expect(held('opacity', 9), closeTo(0.4, 1e-9));
    });
  });

  // 🗣️key-paste-across-lanes-keeps-the-raw-value-Q1 (유저 2026-10-22): 「AE
  // 그대로 — 같은 종류의 데이터끼리」 — a position's 1170 went on a scale as
  // 117000%.
  test('a place in space goes on a place alone — a position\'s key on an '
      'anchor as it is, on a scale neither paste lit', () {
    final place = CanvasPoint(x: 1170, y: 300);
    final track = now().transformTrack;
    s.laneVerbs.updateLayerTransformTrack(
      before.id,
      track.copyWith(
        position: track.position.withKey(3, place).withKeyName(3, 'A'),
      ),
    );
    standOn('position', at: 3);
    pill.copyFrame();
    final scale = now().transformTrack.scale;

    standOn('scale', at: 8);
    expect(
      (pill.canPasteIndependentFrame, pill.canPasteLinkedFrame),
      (false, false),
    );
    pill.pasteIndependentFrame();
    expect(now().transformTrack.scale, scale);

    standOn('anchor-point', at: 8);
    expect(
      (pill.canPasteIndependentFrame, pill.canPasteLinkedFrame),
      (true, true),
    );
    pill.pasteIndependentFrame();
    expect(now().transformTrack.anchorPoint.keys[8]?.value, place);
  });

  // I-65: where a cel number stands is a transform's lanes — its Position a
  // place, its Scale a scale.
  test('a cel number\'s Position is a place — on a layer\'s Position as it '
      'is, on its own Scale neither paste lit', () {
    s.effectsAndFx.addEffectToActiveLayer(EffectKind.celNumber);
    final number = now().effects.single.id;
    s.laneVerbs.setLaneValueAt(
      before.id,
      effectLaneId(number, 'position'),
      3,
      '1170, 300',
      frameIsGlobal: false,
      description: 'Type',
      scaleLinked: false,
    );
    standOn(effectLaneId(number, 'position'), at: 3);
    pill.copyFrame();
    final scale = now().effects.single.stand.scale;

    standOn(effectLaneId(number, 'scale'), at: 8);
    expect(
      (pill.canPasteIndependentFrame, pill.canPasteLinkedFrame),
      (false, false),
    );
    pill.pasteIndependentFrame();
    expect(now().effects.single.stand.scale, scale);

    // Unnamed, it has no name to keep: the independent paste alone is lit.
    standOn('position', at: 8);
    expect(
      (pill.canPasteIndependentFrame, pill.canPasteLinkedFrame),
      (true, false),
    );
    pill.pasteIndependentFrame();
    expect(
      now().transformTrack.position.keys[8]?.value,
      CanvasPoint(x: 1170, y: 300),
    );
  });

  // I-132: a plugin's ids are its own — 'center' is a number of this one
  // and 'amount' its point, where a radial blur has them the other way
  // round. A copy is what its own row said of it, never its id.
  group('a plugin\'s lane goes as its plugin says, whatever its id', () {
    final plugin = FxPluginDescription.fromJson({
      'spec': 1,
      'id': 'com.example.swap',
      'name': 'Swap',
      'vendor': 'Example',
      'version': '1',
      'can': ['cpu'],
      'params': [
        {
          'id': 'center',
          'kind': 'number',
          'label': 'Centre',
          'default': 0,
          'min': 0,
          'max': 10,
        },
        {'id': 'amount', 'kind': 'point', 'label': 'Amount'},
      ],
    })!;
    late EffectId fx;
    setUp(() {
      s.effectsAndFx.addEffectToActiveLayer(EffectKind.plugin, plugin: plugin);
      fx = now().effects.single.id;
    });

    void typed(String lane, int frame, String value) =>
        s.laneVerbs.setLaneValueAt(
          before.id,
          effectLaneId(fx, lane),
          frame,
          value,
          frameIsGlobal: false,
          description: 'Type',
          scaleLinked: false,
        );

    test('its number goes on an opacity as the number it shows', () {
      typed('center', 4, '5');
      standOn(effectLaneId(fx, 'center'), at: 4);
      pill.copyFrame();

      standOn('opacity', at: 9);
      pill.pasteIndependentFrame();

      expect(
        now().transformTrack.opacity.keys[9]?.value,
        closeTo(0.05, 1e-9),
      );
    });

    test('its point is a place — on a cel number\'s Scale neither paste '
        'lit, on a layer\'s Position as it is', () {
      s.effectsAndFx.addEffectToActiveLayer(EffectKind.celNumber);
      final number = now().effects.last.id;
      typed('amount', 3, '1170, 300');
      standOn(effectLaneId(fx, 'amount'), at: 3);
      pill.copyFrame();
      final scale = now().effects.last.stand.scale;

      standOn(effectLaneId(number, 'scale'), at: 8);
      expect(
        (pill.canPasteIndependentFrame, pill.canPasteLinkedFrame),
        (false, false),
      );
      pill.pasteIndependentFrame();
      expect(now().effects.last.stand.scale, scale);

      standOn('position', at: 8);
      pill.pasteIndependentFrame();
      expect(
        now().transformTrack.position.keys[8]?.value,
        CanvasPoint(x: 1170, y: 300),
      );
    });
  });

  // I-132-Q10: a colour key's colour is a colour lane as a cel number's ink
  // is — keyed in one type, so the paste's 「같은 종류의 데이터끼리」 holds.
  test('a colour goes on a colour alone — a key colour on a cel number\'s '
      'ink as it is, on an opacity neither paste lit', () {
    s.effectsAndFx.addEffectToActiveLayer(EffectKind.colorKey);
    s.effectsAndFx.addEffectToActiveLayer(EffectKind.celNumber);
    final [key, number] = [for (final effect in now().effects) effect.id];
    s.laneVerbs.setLaneValueAt(
      before.id,
      effectLaneId(key, 'keyColor'),
      3,
      '#C80A1E',
      frameIsGlobal: false,
      description: 'Type',
      scaleLinked: false,
    );
    standOn(effectLaneId(key, 'keyColor'), at: 3);
    pill.copyFrame();
    final opacity = now().transformTrack.opacity;

    standOn('opacity', at: 8);
    expect(
      (pill.canPasteIndependentFrame, pill.canPasteLinkedFrame),
      (false, false),
    );
    pill.pasteIndependentFrame();
    expect(now().transformTrack.opacity, opacity);

    standOn(effectLaneId(number, 'ink'), at: 8);
    expect(pill.canPasteIndependentFrame, isTrue);
    pill.pasteIndependentFrame();
    expect(now().effects.last.colors['ink']!.keys[8]?.value, 0xFFC80A1E);
  });

  group('where none of the copied lanes is there', () {
    late EffectId gradeA;
    late EffectId gradeB;
    double? keyed(EffectId effect, String parameter, int frame) => now()
        .effects
        .firstWhere((it) => it.id == effect)
        .parameters[parameter]!
        .track
        .keys[frame]
        ?.value;
    void type(EffectId effect, String parameter, int frame, String value) =>
        s.laneVerbs.setLaneValueAt(
          before.id,
          effectLaneId(effect, parameter),
          frame,
          value,
          frameIsGlobal: false,
          description: 'Type',
          scaleLinked: false,
        );

    setUp(() {
      s.effectsAndFx.addEffectToActiveLayer(EffectKind.brightnessContrast);
      s.effectsAndFx.addEffectToActiveLayer(EffectKind.brightnessContrast);
      gradeA = now().effects.first.id;
      gradeB = now().effects.last.id;
    });

    test('several pair with the lanes in order, as a frame copy\'s rows '
        'pair with a band\'s', () {
      type(gradeA, 'brightness', 4, '1');
      type(gradeA, 'contrast', 4, '2');
      expect(keyed(gradeA, 'contrast', 4), 2, reason: '⛔전제');
      standOn(effectGroupLaneId(gradeA), at: 4);
      pill.copyFrame();

      standOn(effectGroupLaneId(gradeB), at: 6);
      pill.pasteIndependentFrame();

      expect((keyed(gradeB, 'brightness', 6), keyed(gradeB, 'contrast', 6)), (1, 2));
    });

    test('one goes on every lane of its kind — 「모든 행에 같은 것을」', () {
      key('rotation', {20: 0.5});
      standOn('rotation', at: 20);
      pill.copyFrame();

      standOn(effectGroupLaneId(gradeB), at: 10);
      pill.pasteIndependentFrame();

      expect(
        (keyed(gradeB, 'brightness', 10), keyed(gradeB, 'contrast', 10)),
        (0.5, 0.5),
      );
    });
  });

  // 🗣️F-388-Q2 (유저 2026-10-20): 「이름 있는 키만 링크 — 그냥 생각할것도없이
  // 프레임블록 복붙이랑 똑같은 규칙」 · I-71 (10-05): 「기존에 이름 존재한다면
  // 링크시킬지 묻는것도 띄우고」.
  group('링크 붙여넣기', () {
    test('keeps each key\'s name — on its own lane the name\'s key, asking '
        'nothing', () {
      key('rotation', {7: 20}, name: 'A');
      standOn('rotation', at: 7);
      pill.copyFrame();

      standOn('rotation', at: 2);
      expect(pill.canPasteLinkedFrame, isTrue);
      pill.pasteLinkedFrame();

      final keys = now().transformTrack.rotation.keys;
      expect((keys[2]?.name, keys[2]?.value), ('A', 20));
      expect((keys[8]?.name, keys[8]?.value), ('A', 20));
    });

    test('has nothing to keep of unnamed keys — the independent paste alone '
        'is lit', () {
      key('rotation', {7: 20});
      standOn('rotation', at: 7);
      pill.copyFrame();

      standOn('rotation', at: 2);
      expect(
        (pill.canPasteIndependentFrame, pill.canPasteLinkedFrame),
        (true, false),
      );
    });

    test('🚨under a name the lane holds at another value it asks first — '
        'and joined, the key takes what the name holds there', () {
      key('rotation', {7: 0.8}, name: 'A');
      key('opacity', {20: 0.3}, name: 'A');
      standOn('rotation', at: 7);
      pill.copyFrame();

      standOn('opacity', at: 2);
      pill.pasteLinkedFrame();
      expect(
        now().transformTrack.opacity.keys.keys,
        [20],
        reason: 'with no window to ask in, nothing is written',
      );
      expect(s.keyClipboard.pasteLinked(), {'A'});
      expect(now().transformTrack.opacity.keys.keys, [20]);

      expect(s.keyClipboard.pasteLinked(joinTakenNames: true), isNull);
      final keys = now().transformTrack.opacity.keys;
      expect((keys[2]?.name, keys[2]?.value), ('A', 0.3));
      expect(keys[21]?.value, 0.3, reason: 'the name\'s key, moved back');
    });

    test('a name only the keys a selection replaces held is free — the key '
        'brings its own value, asking nothing', () {
      key('rotation', {7: 80}, name: 'A');
      key('opacity', {12: 0.3}, name: 'A');
      standOn('rotation', at: 7);
      pill.copyFrame();

      select('opacity', 11, 14);
      expect(s.keyClipboard.pasteLinked(), isNull);

      final keys = now().transformTrack.opacity.keys;
      expect(keys.keys, [11]);
      expect(
        (keys[11]?.name, keys[11]?.value),
        ('A', 0.8),
        reason: '80° shows 80, and 80 on an opacity is 80%',
      );
    });
  });

  test('one undo takes the whole paste back; on the layer row the keys in '
      'hand go nowhere', () {
    key('rotation', {3: 10, 7: 20});
    standOn('rotation', at: 3);
    pill.copyFrame();
    standOn('rotation', at: 0);
    pill.pasteIndependentFrame();
    expect(rotation(), {0: 10, 4: 10, 8: 20}, reason: '⛔전제');

    s.undo();
    expect(rotation(), {3: 10, 7: 20});

    s.selectFrameIndex(0);
    s.standOnRow(LayerRowAddress(before.id));
    expect(pill.canPasteIndependentFrame, isFalse);
    pill.pasteIndependentFrame();
    expect(rotation(), {3: 10, 7: 20});
  });
}
