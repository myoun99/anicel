import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId;
import 'package:anicel/src/ui/timeline/timeline_bar_menus.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// 🗣️I-99 (유저 2026-10-14): 「콘티패널에서 콘티작업중 일부 레이어에만
/// 트랜스폼 조정하거나 fx걸고싶은데 그게 불가능해서」.
///
/// Standing on a row of the conte group in the storyboard holds the
/// timeline's own row (F-322), so the fx menu's adds — and a paste of
/// effects, which is an add of them — are the timeline's there. Off such a
/// row the list stays grey, as it always was — but on the V row, whose own
/// chain takes them (-Q1).
///
/// Cuts a [0, 12) and b [12, 24) each hold a conte and a row riding over
/// it; four frames of gap; then c [28, 40), which has no conte.
void main() {
  const trackId = TrackId('t1');
  const hue = EffectId('hue');
  final conteRow = LayerRowAddress(trackConteRowId(trackId));
  final over = LayerRowAddress(trackConteRowId(trackId, seat: 1));

  Layer drawn(
    String id, {
    LayerKind kind = LayerKind.storyboard,
    String? ridesOn,
    List<LayerEffect> effects = const [],
  }) => Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    attachedToLayerId: ridesOn == null ? null : LayerId(ridesOn),
    attachedPlacement: AttachedPlacement.above,
    attachedMode: AttachedMode.free,
    effects: effects,
    frames: [Frame(id: FrameId('$id-0'), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-0'), length: 12)},
  );

  Cut cutOf(String id, {bool conte = true, int gap = 0}) => Cut(
    id: CutId(id),
    name: id,
    duration: 12,
    leadingGapFrames: gap,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      drawn(
        '$id-cel',
        kind: LayerKind.animation,
        effects: [
          LayerEffect.defaults(id: hue, kind: EffectKind.hueSaturation),
        ],
      ),
      if (conte) ...[
        drawn('$id-conte'),
        drawn('$id-over', ridesOn: '$id-conte'),
      ],
      Layer(
        id: LayerId('$id-cam'),
        name: 'Camera',
        kind: LayerKind.camera,
        frames: const [],
      ),
    ],
  );

  EditorSessionManager sessionOf() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('conte-fx'),
        name: 'Conte fx',
        createdAt: DateTime.utc(2026, 10, 28),
        tracks: [
          Track(
            id: trackId,
            name: 'V1',
            cuts: [
              cutOf('a'),
              cutOf('b'),
              cutOf('c', conte: false, gap: 4),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  EditorSessionManager standingAt(TimelineRowAddress row, int frame) {
    final session = sessionOf()
      ..standOnRow(
        row,
        panel: WorkingPanel.storyboard,
        globalFrameIndex: frame,
      );
    expect(session.storyboardStandingRow, row, reason: 'fixture: standing');
    return session;
  }

  /// The fx menu's add of [kind], as the bar [panel] heads draws it.
  PanelFlyoutItem addOf(
    EditorSessionManager session,
    ToolbarPanelContext panel,
    EffectKind kind,
  ) => TimelineBarMenus(session: session, panel: panel)
      .effects()
      .whereType<PanelFlyoutItem>()
      .firstWhere((item) => item.keyValue == 'add-effect-${kind.jsonValue}');

  List<EffectKind> effectsOf(EditorSessionManager session, String id) => [
    for (final cut in session.repository.requireProject().tracks.single.cuts)
      for (final layer in cut.layers)
        if (layer.id == LayerId(id))
          for (final effect in layer.effects) effect.kind,
  ];

  test('on the conte row the fx menu adds as the timeline\'s does on the '
      'same row — its shape on every cut\'s conte', () {
    final session = standingAt(conteRow, 3);
    final storyboard = StoryboardToolbarPanelContext(session);
    final timeline = TimelineToolbarPanelContext(
      sessionOf()
        ..selectCut(const CutId('a'))
        ..standOnRow(const LayerRowAddress(LayerId('a-conte'))),
    );
    for (final kind in effectKindsAddedAlone) {
      expect(
        addOf(session, storyboard, kind).enabled,
        addOf(timeline.session, timeline, kind).enabled,
        reason: '$kind',
      );
    }

    final add = addOf(session, storyboard, EffectKind.blur);
    expect(add.enabled, isTrue);
    add.onSelected!();
    expect(effectsOf(session, 'a-conte'), [EffectKind.blur]);
    expect(
      effectsOf(session, 'b-conte'),
      [EffectKind.blur],
      reason: 'the chain\'s shape is the head\'s (I-73)',
    );
  });

  test('on a row riding the conte it adds to that row — its own fx, apart '
      'from the conte\'s', () {
    final session = standingAt(over, 3);
    final add = addOf(
      session,
      StoryboardToolbarPanelContext(session),
      EffectKind.blur,
    );
    expect(add.enabled, isTrue);
    add.onSelected!();
    expect(effectsOf(session, 'a-over'), [EffectKind.blur]);
    expect(effectsOf(session, 'b-over'), [EffectKind.blur]);
    expect(effectsOf(session, 'a-conte'), isEmpty);
  });

  test('effects in hand paste onto the conte row as an add of them', () {
    final session = sessionOf()..selectCut(const CutId('a'));
    session.rowSelectionVerbs.beginRowSelection(
      LaneRowAddress(const LayerId('a-cel'), effectGroupLaneId(hue)),
    );
    TimelineToolbarPanelContext(session).copyFrame();
    expect(session.effectClipboard.holdsEffects, isTrue, reason: '⛔전제');

    session.standOnRow(
      conteRow,
      panel: WorkingPanel.storyboard,
      globalFrameIndex: 3,
    );
    final storyboard = StoryboardToolbarPanelContext(session);
    expect(storyboard.canPasteIndependentFrame, isTrue);
    storyboard.pasteIndependentFrame();
    expect(effectsOf(session, 'a-conte'), [EffectKind.hueSaturation]);
  });

  group('🗣️-Q1 (유저 2026-10-30, 「공용 Fx 가 V행도 받는다」): on the V row it '
      'adds to the V row\'s chain', () {
    List<EffectKind> trackChainOf(EditorSessionManager session) => [
      for (final effect
          in session.repository.requireProject().tracks.single.effects)
        effect.kind,
    ];

    List<EffectKind> everyLayersEffects(EditorSessionManager session) => [
      for (final cut in session.repository.requireProject().tracks.single.cuts)
        for (final layer in cut.layers)
          for (final effect in layer.effects) effect.kind,
    ];

    test('every kind it can hold is lit, a cel number not — and the add '
        'lands on the track, not on the row the timeline holds', () {
      final session = standingAt(const TrackRowAddress(trackId), 3);
      final storyboard = StoryboardToolbarPanelContext(session);
      for (final kind in effectKindsAddedAlone) {
        expect(
          addOf(session, storyboard, kind).enabled,
          !kind.drawsItsOwnPicture,
          reason: '$kind',
        );
      }
      final layersBefore = everyLayersEffects(session);

      addOf(session, storyboard, EffectKind.blur).onSelected!();
      expect(trackChainOf(session), [EffectKind.blur]);
      expect(everyLayersEffects(session), layersBefore);
    });

    test('effects in hand paste onto it as an add of them', () {
      final session = sessionOf()..selectCut(const CutId('a'));
      session.rowSelectionVerbs.beginRowSelection(
        LaneRowAddress(const LayerId('a-cel'), effectGroupLaneId(hue)),
      );
      TimelineToolbarPanelContext(session).copyFrame();
      expect(session.effectClipboard.holdsEffects, isTrue, reason: '⛔전제');

      session.standOnRow(
        const TrackRowAddress(trackId),
        panel: WorkingPanel.storyboard,
        globalFrameIndex: 3,
      );
      final storyboard = StoryboardToolbarPanelContext(session);
      expect(storyboard.canPasteIndependentFrame, isTrue);
      storyboard.pasteIndependentFrame();
      expect(trackChainOf(session), [EffectKind.hueSaturation]);
      expect(effectsOf(session, 'a-cel'), [EffectKind.hueSaturation]);
    });
  });

  group('🚨off a row of a cut\'s conte or the V row the list stays grey', () {
    void expectGrey(EditorSessionManager session) {
      final storyboard = StoryboardToolbarPanelContext(session);
      expect(storyboard.effectChainHolder, isNull);
      for (final kind in effectKindsAddedAlone) {
        expect(
          addOf(session, storyboard, kind).enabled,
          isFalse,
          reason: '$kind',
        );
      }
    }

    test('the conte row over a cut with no conte — the timeline holds a '
        'drawing row there, which is not this row', () {
      final session = sessionOf()
        ..selectCut(const CutId('c'))
        ..standOnRow(const LayerRowAddress(LayerId('c-cel')))
        ..standOnRow(
          conteRow,
          panel: WorkingPanel.storyboard,
          globalFrameIndex: 30,
        );
      expect(session.activeLayerId, const LayerId('c-cel'), reason: '⛔전제');
      expect(
        session.effectsAndFx.canAddEffectToActiveLayer(EffectKind.blur),
        isTrue,
        reason: '⛔전제: the row the timeline holds takes effects',
      );
      expectGrey(session);
    });
  });
}
