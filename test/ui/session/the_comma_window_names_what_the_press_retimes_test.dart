import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/storyboard_cursor.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';
import '../../helpers/a_cut_with_a_drawing_row.dart';

/// 🗣️I-24-open-entry (유저 2026-10-01): 「노출 길이 설정 (프레임), 노출 길이
/// 설정 (컷) 이렇게 하자 … 길이 설정도 기존 길이 띄워둔다는뜻」.
///
/// The N window names what the press re-times and opens on its length, read
/// off the press's own ladder — the rung that would take the press is the
/// one the window describes. Every case stands in the SECOND cut, where a
/// track row's keys and the cut's frames differ.
///
/// The collaborator the law lives in — named so `tool/mutation_run.dart`
/// runs this file for it.
StoryboardCursor cursorOf(EditorSessionManager session) =>
    session.storyboardCursor;

typedef _Shown = ({List<CommaTargetKind> kinds, int? length});

void main() {
  late EditorSessionManager session;
  late LayerId s1;
  late int cut2;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    s1 = session.activeTrack.seLayers.first.id;
    createCutWithADrawingRow(session);
    cut2 = session.activeCutGlobalStartFrame;
    expect(cut2, greaterThan(0), reason: 'fixture premise: the second cut');
  });
  tearDown(() => session.dispose());

  _Shown? shown(CommaTarget? target) =>
      target == null ? null : cursorOf(session).commaTargetShown(target);
  _Shown? onTimeline() => shown(cursorOf(session).timelineCommaTarget());
  _Shown? onStoryboard() => shown(cursorOf(session).storyboardCommaTarget());

  /// [CommaTargetKind]s and a length, as the window shows them — a record
  /// holding a list compares it by identity, so the fields are matched.
  Matcher isShown(List<CommaTargetKind> kinds, int? length) => isA<_Shown>()
      .having((shown) => shown.kinds, 'kinds', kinds)
      .having((shown) => shown.length, 'length', length);

  void placeSound(int localFrame, {required int length}) {
    session.selectLayer(s1);
    session.selectFrameIndex(localFrame);
    session.seEntries.createSeEntryAtCurrentFrame(
      name: 'se$localFrame',
      lengthFrames: length,
    );
  }

  /// A conte row cut at frame 5 — panels of 5 and 19 — and its id.
  LayerId conteOfFiveAndNineteen() {
    session.layerStack.addLayerOfKind(LayerKind.storyboard);
    session.selectFrameIndex(5);
    session.createDrawingAtCurrentFrame();
    final conte = storyboardLayerForCut(session.requireActiveCut)!.id;
    expect(
      [
        for (final entry in session.layerById(conte)!.timeline.entries)
          (entry.key, entry.value.length),
      ],
      [(0, 5), (5, 19)],
      reason: 'fixture',
    );
    return conte;
  }

  void standOnStoryboard(TimelineRowAddress row, int localFrame) =>
      session.standOnRow(
        row,
        panel: WorkingPanel.storyboard,
        globalFrameIndex: cut2 + localFrame,
      );

  group('a block under the cursor', () {
    test('a cel is a frame, at its length — and the length it is given '
        'next', () {
      final cel = session.layers
          .firstWhere((layer) => layer.kind == LayerKind.animation)
          .id;
      session.selectLayer(cel);
      session.selectFrameIndex(0);
      session.createDrawingAtCurrentFrame();

      expect(onTimeline(), isShown([CommaTargetKind.frame], 1));
      session.edgeDrag.setCommaForTimelineCursor(3);
      expect(onTimeline(), isShown([CommaTargetKind.frame], 3));
    });

    test('a sound is an SE, at its length', () {
      placeSound(3, length: 2);
      session.selectFrameIndex(4);

      expect(onTimeline(), isShown([CommaTargetKind.se], 2));
    });

    test('a transition span is a transition, at its length', () {
      session.selectLayer(session.activeTrack.transitionLayer.id);
      session.selectFrameIndex(2);
      session.transitions.createTransitionSpanInCut();
      session.edgeDrag.setCommaForTimelineCursor(6);

      expect(onTimeline(), isShown([CommaTargetKind.transition], 6));
    });

    test('the storyboard\'s V row is the cut, at the cut\'s length', () {
      standOnStoryboard(TrackRowAddress(session.selectedTrackId), 1);

      expect(
        onStoryboard(),
        isShown([CommaTargetKind.cut], session.requireActiveCut.duration),
      );
    });

    test('its conte row is a panel — a frame — at the panel\'s length', () {
      conteOfFiveAndNineteen();
      standOnStoryboard(
        LayerRowAddress(trackConteRowId(session.selectedTrackId)),
        6,
      );

      expect(onStoryboard(), isShown([CommaTargetKind.frame], 19));
    });

    test('nothing under the cursor names nothing — the window does not '
        'open', () {
      session.selectLayer(s1);
      session.selectFrameIndex(10);

      expect(onTimeline(), isNull);
    });
  });

  group('a band', () {
    void sweepConteAndSound(LayerId conte) =>
        session.frameRangeSelection.value = TimelineFrameRangeSelection(
          layerId: conte,
          startIndex: 0,
          endIndexExclusive: 5,
          layerIds: [conte, s1],
        );

    test('names every kind it holds, in one order, and opens empty where '
        'its blocks disagree', () {
      final conte = conteOfFiveAndNineteen();
      placeSound(2, length: 2);
      sweepConteAndSound(conte);

      expect(
        onTimeline(),
        isShown([CommaTargetKind.frame, CommaTargetKind.se], null),
      );
    });

    test('opens on the length its blocks agree on — each read in its own '
        'row\'s keys', () {
      final conte = conteOfFiveAndNineteen();
      placeSound(2, length: 5);
      sweepConteAndSound(conte);

      expect(
        onTimeline(),
        isShown([CommaTargetKind.frame, CommaTargetKind.se], 5),
        reason: 'the sound is keyed on the track\'s axis at ${cut2 + 2}',
      );
    });

    test('the storyboard\'s band on the track\'s axis, the same way', () {
      placeSound(0, length: 3);
      placeSound(3, length: 3);
      session.rangeSelections.updateTrackRowRangeSelectionByFrame(
        layerId: s1,
        anchorGlobalFrame: cut2,
        headGlobalFrame: cut2 + 3,
      );

      expect(onStoryboard(), isShown([CommaTargetKind.se], 3));
    });
  });
}
