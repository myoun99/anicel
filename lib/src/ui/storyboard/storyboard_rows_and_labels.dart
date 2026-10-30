part of '../storyboard_panel.dart';

/// THE ROWS AND THEIR LABELS — the SE and transition label rows, the
/// transition strip row, and the draggable versions of the track-effect
/// and SE rows — as their own object.
///
/// 🚨A collaborator carved out of `_StoryboardPanelState` (the audit's SRP
/// cut, 2026-09-02). It reaches the State through `_state`.
class _StoryboardRowsAndLabels {
  _StoryboardRowsAndLabels(this._state);

  final _StoryboardPanelState _state;

  /// What the rail keeps of its rows ([_KeptRailRows]).
  final _KeptRailRows _kept = _KeptRailRows();

  /// A lane list's labels — [rowId]'s lanes, row for row with [lanes] —
  /// laid as the table lays the lanes ([_laidLanes]), each made to select
  /// ([selectOnly]) by the address it is stood on, and each fx GROUP HEADER
  /// made to re-order [chainId]'s chain too: the layer rail's gesture.
  ///
  /// 🗣️I-89 ①ⓓ (유저 2026-10-13: 「이런건 다 콘티패널에도 동일하게
  /// 있어야해. 같은 법으로」): every row this rail twirls down orders its fx
  /// here as the timeline's rail does — the V row's chain on its lane
  /// carrier, an S row's on its layer, a projection row's on its layer in the
  /// cut the session stands in. ↩️The V row alone did
  /// (`draggableTrackEffectRows`); an S row's and a conte row's headers only
  /// selected (`selectableLanes`).
  ///
  /// A null [chainId] leaves the headers to select like every lane: a
  /// projection row with nothing stood in edits nothing (I-73 ④).
  ///
  /// The pointer counts LANE rows and the chain counts HEADERS, and the two
  /// differ the moment a group is twirled open — which is exactly when
  /// someone reaches for the order. [rowStepsBetween] converts, the same
  /// way the timeline's rail does it.
  List<Widget> laneRows(
    LayerId rowId,
    List<PropertyLaneRow> lanes,
    List<Widget> rows, {
    required LayerId? chainId,
  }) {
    final chain = (
      rowId: rowId,
      chainId: chainId,
      headers: [
        for (final (index, lane) in lanes.indexed)
          if (parseEffectLaneId(lane.laneId) case (
            :final effectId,
            parameterId: null,
          ))
            (rowIndex: index, effectId: effectId),
      ],
    );
    return _laidLanes(rowId, lanes, [
      for (var index = 0; index < rows.length; index += 1)
        if (index >= lanes.length)
          rows[index]
        else
          _laneRow(chain, (lane: lanes[index], index: index), rows[index]),
    ]);
  }

  /// One lane label of [chain]'s row at [at]: a group header re-orders the
  /// chain, and selects; every other lane moves nothing, and selects like
  /// every row.
  Widget _laneRow(
    ({
      LayerId rowId,
      LayerId? chainId,
      List<({int rowIndex, EffectId effectId})> headers,
    })
    chain,
    ({PropertyLaneRow lane, int index}) at,
    Widget row,
  ) {
    final hooks = _state.widget.rowDragHooks;
    final chainId = chain.chainId;
    final displayEffects = [
      for (final header in chain.headers) header.effectId,
    ];
    final parsed = parseEffectLaneId(at.lane.laneId);
    final slot = parsed == null || parsed.parameterId != null
        ? -1
        : displayEffects.indexOf(parsed.effectId);
    final extent = _laneExtentOf(chain.rowId, at.lane);
    final address = LaneRowAddress(chain.rowId, at.lane.laneId);
    if (hooks == null || chainId == null || slot < 0) {
      return selectOnly(
        LaneRowSubject(chain.rowId, at.lane.laneId),
        extent,
        row,
      );
    }
    return LayerRowDragTarget(
      subject: EffectRowSubject(chainId, parsed!.effectId),
      slotBefore: slot,
      rowExtent: extent,
      // I-89 ③: the room an open graph stands past its lanes is no row.
      pointerRowsAt: _state._railRows.pointerRowsFrom(address),
      axis: Axis.horizontal,
      hooks: hooks,
      grip: () => [effectRowDragChip(at.lane)],
      drawsTheGapAfter: slot == displayEffects.length - 1,
      linesBeyond: _state._railRows.linesBeyondFrom(address),
      onCrossed: (steps, _, _) => hooks.onEffectUpdate(
        chainId,
        displayEffects,
        slotForSteps(
          slot,
          rowStepsBetween(
            [for (final header in chain.headers) header.rowIndex],
            at.index,
            steps,
          ),
          displayEffects.length,
        ),
      ),
      // B4-3's select half, as the timeline's chain header has it — from
      // the row the rail draws, which a projection row's chain is not.
      onSelectCrossed: _spanOnSelect(),
      selectRowDeltaAt: _state._railRows.selectRowDeltaFrom(address),
      child: row,
    );
  }

  /// THE RAIL'S SELECT HALF (🗣️F-322, 유저 2026-10-09: 「콘티패널 지금
  /// 옛날부터 몇번말해도 계속 레이어의 선택범위 작동안하고 바로
  /// 드래그방식인데 작동하도록. 타임라인이랑 완벽통일」): a span over every row
  /// this rail draws ([_StoryboardSheet.rows]), every track's and of every
  /// kind — the timeline rail's own law, 「선택범위는 레이어 불문 자유롭게」.
  /// Null while the host wired no span.
  ///
  /// ↩️The S rows took a span over the S rows alone, and no other row of
  /// this rail took one at all: a span from an S row stopped short of the V
  /// row, and the conte rows, the camera row and the transition row could
  /// not start one.
  void Function(int rowDelta)? _spanOnSelect() {
    if (_state.widget.onRowSelectionSpan == null) {
      return null;
    }
    // The host's span as it stands at the event: a kept row's wrapper
    // outlives the build it was made in ([_KeptRailRows]).
    return (rowDelta) =>
        _state.widget.onRowSelectionSpan?.call(_state._sheet.rows(), rowDelta);
  }

  /// [child], a row that moves nothing on this rail, made to SELECT: a drag
  /// on it starts a span, and pressed inside one it lifts with it and
  /// settles where it was (F-16-Q1) — the shape the timeline's unmovable
  /// rows take ([LayerRowDragTarget.selectOnly]). [child] alone while the
  /// host wired no selection.
  Widget selectOnly(
    LayerRowDragSubject subject,
    double rowExtent,
    Widget child, {
    List<DragChipItem> Function()? grip,
  }) {
    final hooks = _state.widget.rowDragHooks;
    final span = _spanOnSelect();
    if (hooks == null || hooks.onSelectBegin == null || span == null) {
      return child;
    }
    return LayerRowDragTarget.selectOnly(
      subject: subject,
      rowExtent: rowExtent,
      axis: Axis.horizontal,
      hooks: hooks,
      onSelectCrossed: span,
      selectRowDeltaAt: _state._railRows.selectRowDeltaFrom(
        timelineRowAddressOfDragSubject(subject),
      ),
      grip: grip,
      child: child,
    );
  }

  /// What [selectOnly] builds a row's wrapper from: the row's [subject] and
  /// [rowExtent], and the host's half ([_dragInputs]).
  Object? _selectOnlyInputs(LayerRowDragSubject subject, double rowExtent) =>
      (subject, rowExtent, _dragInputs);

  /// The host's half of what a row's drag wrapper is built from: its hooks,
  /// which the host binds once, and whether it wired a span. Whatever else
  /// of the host a wrapper reaches, it asks at the event.
  Object? get _dragInputs => (
    ByIdentity(_state.widget.rowDragHooks),
    _state.widget.onRowSelectionSpan != null,
  );

  /// [build]'s rail rows — every track's — kept as one pass
  /// ([_KeptRailRows.pass]).
  List<Widget> railPass(List<Widget> Function() build) => _kept.pass(build);

  /// [label] in the drag wrapper [wrap] puts on it — the rail's row [key] —
  /// kept while [label]'s facts and [inputs], what [wrap] builds the
  /// wrapper from, hold ([_KeptRailRows]); wearing, as a head, the layer
  /// its row has in hand now ([_wearing]), which a kept row may have been
  /// built for another of.
  Widget _keptRow(
    Object key,
    _RailLabel label,
    Object? inputs,
    Widget Function(Widget label) wrap,
  ) {
    final piece = label.piece;
    final row = _kept.keep(
      key,
      (inputs, piece.runtimeType, piece.facts),
      () => wrap(piece),
    );
    return switch (label.wears) {
      final wears? => _wearing(wears, row),
      null => row,
    };
  }

  /// [label] made to select ([selectOnly]) as [subject]'s row, [rowExtent]
  /// tall, and kept ([_keptRow]) as the rail's row of [subject] — the one
  /// row it names; its [grip] is asked at the press.
  Widget _keptSelectOnly(
    _RailLabel label,
    LayerRowDragSubject subject,
    double rowExtent, {
    required List<DragChipItem> Function() grip,
  }) => _keptRow(
    subject,
    label,
    _selectOnlyInputs(subject, rowExtent),
    (label) => selectOnly(subject, rowExtent, label, grip: grip),
  );

  /// [label] standing alone, as the folded overlay shows it — wearing, as
  /// a head, the layer its row has in hand ([_wearing]).
  Widget _labelAlone(_RailLabel label) => switch (label.wears) {
    final wears? => _wearing(wears, label.piece),
    null => label.piece,
  };

  /// [rows] — [carrierId]'s lane labels, row for row with [lanes] — laid as
  /// the table lays the lanes (I-89 ①, [_StoryboardRailRows._seatedLane]):
  /// none for a lane of no extent — an open graph folded stands as its
  /// first lane's strip — and an open graph's room after its last lane,
  /// which is no row, as the timeline's rail lays them.
  List<Widget> _laidLanes(
    LayerId carrierId,
    List<PropertyLaneRow> lanes,
    List<Widget> rows,
  ) => [
    for (var index = 0; index < rows.length; index += 1)
      if (index < lanes.length
          ? _seatedOf(carrierId, lanes[index])
          : null case final seated?) ...[
        if (seated.extent > 0) rows[index],
        if (seated.room > 0) SizedBox(height: seated.room),
      ] else
        rows[index],
  ];

  /// [carrierId]'s [lane] as the table lays it.
  _SeatedLane? _seatedOf(LayerId carrierId, PropertyLaneRow lane) =>
      _state._railRows._seatedLane(LaneRowAddress(carrierId, lane.laneId));

  /// How far [carrierId]'s [lane] stands on the rail ([_seatedOf]).
  double _laneExtentOf(LayerId carrierId, PropertyLaneRow lane) =>
      _seatedOf(carrierId, lane)?.extent ?? _state._rowHeights.lane;

  /// Lane rail label rows on the shared substrate — an S row's lanes
  /// ([_StoryboardRailRows._seLanes]) or a V row's fx chain
  /// ([_StoryboardRailRows._trackEffectLanes]): the group headers plus the
  /// twirled-open member lanes, storyboard-prefixed. [active] gates the
  /// navigator's frame jumps and value edits; what they edit with, and at
  /// which frame, is [carrier]'s row's hand
  /// ([_StoryboardRailRows._laneHandOf]) — the column sweep's too.
  List<Widget> laneLabels({
    required Layer carrier,
    required List<PropertyLaneRow> lanes,
    required bool active,

    /// The group each header twirls, per LANE, by [laneGroupKey] on the row
    /// that keeps it — the layer's, a projection row's head's (I-73 ④ⓔ),
    /// the V row's lane carrier — turned by
    /// [StoryboardPanel.onToggleLaneGroupKey], the timeline's verb: a group's
    /// twirl is its row's (F-360).
    ///
    /// ↩️An S and a V row's groups were the rail's own twirls
    /// (`onToggleTransformGroup`), and a list said which verb turned it.
    required String Function(PropertyLaneRow lane) groupKeyOf,
    ValueChanged<int>? onSelectFrame,

    /// The header's own ON/OFF switch (AE's per-effect eyeball). Null leaves
    /// the glyph inert. ↩️「which is what a Transform header wants here」 held
    /// until F-101 gave the S rows the timeline's switch.
    void Function(PropertyLaneRow lane)? onToggleGroupEnabled,

    /// The header's RESET (R5, AE's group Reset). Null hides the button —
    /// a header whose group has no reset route must not show one.
    void Function(PropertyLaneRow lane)? onResetGroup,

    /// How a row FOLLOWS a lane edit in flight (F-195): [row] rebuilt with
    /// the carrier and the lane as the edit shows them, whenever the edit
    /// moves. The timeline's rail does this through its row gate; these
    /// labels are built from lists of their own, so each list says how it
    /// re-derives. Null shows the rows as committed.
    Widget Function(
      Layer carrier,
      PropertyLaneRow lane,
      Widget Function(Layer carrier, PropertyLaneRow lane) row,
    )?
    follow,

    /// What the lanes' header graph buttons and pins tell (I-89 ①) — the
    /// timeline's own verbs, on the timeline's own graphs, as this rail
    /// keys its rows ([_StoryboardRailRows._laneGraphVerbs]). Null mounts
    /// none.
    LaneGraphVerbs? graphVerbs,
  }) {
    final laneHeight = _state._rowHeights.lane;
    final metrics = TimelineGridMetrics(
      frameCellWidth: _state.widget.pixelsPerFrame,
      layerRowHeight: laneHeight - 2,
      railColumns: layerRailColumnWidthsIn(_state.context),
    );
    final toggleGroup = _state.widget.onToggleLaneGroupKey;
    final selection = _state.widget.rowSelection;
    final hand = _state._railRows._laneHandOf(carrier.id);
    Widget row(Layer shown, PropertyLaneRow lane) {
      final seated = _seatedOf(carrier.id, lane);
      Widget label(TimelineGraphSeat? seat) => TimelineLaneControlsRow(
        layer: shown,
        lane: lane,
        metrics: metrics,
        width: _state._naturalRailWidth,
        height: seated?.extent ?? laneHeight,
        frameCursor: hand.cursor,
        onSelectFrame: active ? onSelectFrame : null,
        laneEdit: lane.isGroupHeader || !active ? null : hand.edit,
        onToggleLaneGroup: toggleGroup == null
            ? null
            : (_, _) => toggleGroup(groupKeyOf(lane)),
        onToggleLaneGroupEnabled: onToggleGroupEnabled == null
            ? null
            : (_, _) => onToggleGroupEnabled(lane),
        onResetLaneGroup: onResetGroup == null || !lane.isGroupHeader
            ? null
            : (_, _) => onResetGroup(lane),
        keyPrefix: 'storyboard',
        leadingInset: layerSectionLabelSlotWidth,
        optionalColumns: StoryboardPanel.optionalRailColumns,
        currentRowHooks: _state.widget.currentRowHooks,
        // As this rail keys its rows: a projection row's by its own id.
        laneGraphs: _state._railRows._laneGraphs,
        laneGraphVerbs: graphVerbs,
        seat: seat,
        folded: seated?.row.folded ?? false,
      );
      // What an open graph draws follows the row selection, which this rail
      // draws on a listener of its own ([_StoryboardRailRows._seatIn]).
      if (seated == null || seated.row.graph == null || selection == null) {
        return label(seated?.row.graph);
      }
      return ValueListenableBuilder<List<TimelineRowAddress>>(
        valueListenable: selection,
        builder: (context, selected, _) =>
            label(_state._railRows._seatIn(seated, selected)),
      );
    }

    // The track's rows — V and S alike, their keys are the track's — stand
    // on the GLOBAL playhead (R4b, [_StoryboardRailRows._laneHandOf]).
    // ↩️The S rows passed the ACTIVE cut's local cursor until F-102, which
    // put their values and keys at the wrong frame in any cut but the
    // first. Either way the row SUBSCRIBES — itself, on a layer of its own
    // — so a committed seek rebuilds these label cells and lays out nothing
    // else (the timeline rail's own line).
    return [
      for (final lane in lanes)
        if (follow == null) row(carrier, lane) else follow(carrier, lane, row),
    ];
  }

  /// An S row's rail label, made draggable — the rail's row-order drag, on
  /// the third surface.
  ///
  /// No active-cut gate: an S row is a TRACK fixture and re-orders its own
  /// track's list, so which cut is open has nothing to say about it (user,
  /// 2026-08-09: "S행은 V랑 관련없이 독립적으로 움직일 수 있어야 해"). The
  /// gate guarded a session that committed to the SELECTED track; the
  /// commit resolves the row's own track now.
  Widget seLabelRow(Track track, int slot) {
    final layer = _trackSeAt(track, slot);
    final hooks = _state.widget.rowDragHooks;
    if (hooks == null || layer == null) {
      return _seLabel(track, slot);
    }
    final label = _seLabelOf(track, slot, layer);
    final shown = _seShownNow(track);
    final at = shown.indexWhere((row) => row.id == layer.id);
    final extent = _state._railRows._seRowGroupExtent(track, slot);
    final trackId = track.id;
    return _keptRow(
      ('se', trackId, slot),
      label,
      (layer.id, at, shown.length, extent, _dragInputs),
      (label) => LayerRowDragTarget(
        subject: TrackSeRowSubject(trackId, layer.id),
        slotBefore: at,
        rowExtent: extent,
        axis: Axis.horizontal,
        hooks: hooks,
        grip: () => [
          if (_state._railRows._trackNamed(trackId) case final now?)
            ...layerRowDragChips(
              rows: _state._railRows._seRowsInDisplayOrder(now),
              pressed: layer.id,
              hooks: hooks,
            ),
        ],
        drawsTheGapAfter: at == shown.length - 1,
        linesBeyond: _state._railRows.linesBeyondFrom(
          LayerRowAddress(layer.id),
        ),
        // The S rows are a flat SE list — no row here holds another, so
        // there is nothing for an on-row drop to mean and the caret stays
        // the only answer (R5 #15). The rows are the track's at the event:
        // the row is kept while its caret holds, not its neighbours.
        onCrossed: (steps, _, _) {
          final now = _state._railRows._trackNamed(trackId);
          final rows = now == null ? const <Layer>[] : _seShownNow(now);
          final from = rows.indexWhere((row) => row.id == layer.id);
          if (from >= 0) {
            hooks.onUpdate(rows, slotForSteps(from, steps, rows.length));
          }
        },
        // 🚨A5-3② — the SELECT half of the same drag, which this rail
        // simply did not have. ⑨'s law is that the first drag SELECTS and a
        // drag starting INSIDE the selection moves; without these the press
        // went straight to the move here while the timeline made you select
        // first, and 「통일이 안 돼 있다」 was exactly that.
        onSelectCrossed: _spanOnSelect(),
        selectRowDeltaAt: _state._railRows.selectRowDeltaFrom(
          LayerRowAddress(layer.id),
        ),
        child: label,
      ),
    );
  }

  /// [track]'s S rows as the rail shows them, top-down — the track's list
  /// reversed, less the rows the filter hides, as the timeline's display
  /// rows leave them out; `modelInsertionForSlot` infers the rest from the
  /// two lists.
  List<Layer> _seShownNow(Track track) => [
    for (final shown in _state._railRows._shownSeSlots(track))
      ?_trackSeAt(track, shown),
  ];

  /// The transition row's rail label — the timeline's own row for the
  /// transition layer ([_transitionLabelOf]), made to select.
  Widget transitionLabelRow(Track track) {
    final trackId = track.id;
    return _keptSelectOnly(
      _transitionLabelOf(track),
      LayerRowSubject(track.transitionLayer.id),
      _state._rowHeights.transition,
      grip: () => [
        if (_state._railRows._trackNamed(trackId)?.transitionLayer
            case final layer?)
          (icon: layerKindIcon(layer.kind), label: layer.name),
      ],
    );
  }

  /// [transitionLabelRow]'s label alone, [chromeless] on the folded overlay.
  Widget _transitionLabel(Track track, {bool chromeless = false}) =>
      _labelAlone(_transitionLabelOf(track, chromeless: chromeless));

  /// The transition row's label: THE TIMELINE'S OWN ROW for the track's
  /// transition layer ([_StoryboardRailHead]) — the controls its kind
  /// carries there carried here (B5③ 2026-08-17, ordered twice): the sheet
  /// toggle (the kind prints), the mark chip (⑲: the strip's blocks are
  /// painted in the mark colour, so the chip IS this row's colour label)
  /// and the eye, whose subject is the layer's COMPOSITE CONTRIBUTION — a
  /// hidden transition row stops feeding its fades to playback
  /// ([EditorSessionManager.transitionSpansOfTrack]); fx and opacity stay
  /// absent by KIND, as on the timeline.
  ///
  /// ⛔It carries **no verb of its own**. Its label used to hold a `＋`
  /// reading "make one at the playhead", and that button is what the user
  /// was pointing at (2026-08-11): 「프레임생성하는거 행에 버튼만들어서
  /// 넣은거같은데, 그게아니라 인스턴스편집버튼으로 작동하도록. 삭제나 그런거 다
  /// 똑같이」. Create, edit and delete are one verb now —
  /// [editTransitionSpanInstance], reached from the frame pill's Edit
  /// Instance and from the row's double-tap — so a second entrance on the
  /// rail is the predecessor, not a convenience. Everything else the row
  /// can do is a gesture on the strip (grips size the span, a press opens
  /// its term dialog).
  _RailLabel _transitionLabelOf(Track track, {bool chromeless = false}) {
    final widget = _state.widget;
    final layer = track.transitionLayer;
    return (
      piece: _StoryboardRailHead(
        key: ValueKey<String>('storyboard-transition-label-${track.id.value}'),
        rowId: layer.id,
        chromeless: chromeless,
        layer: layer,
        active: widget.selectedRow == LayerRowAddress(layer.id),
        fxState: LayerFxState.on,
        metrics: _headMetrics(_state._rowHeights.transition),
        onSelectLayer: widget.onSelectLayer,
        onSettledPress: widget.onSettledPress,
        labelDoubleClick: widget.labelDoubleClick,
        onToggleLayerVisibility: widget.onToggleLayerVisibility,
        onLayerMarkSelected: widget.onLayerMarkSelected,
        onToggleLayerTimesheet: _sheetToggleOf(layer.id),
        // The rail's blend column, its slot kept empty by the kind.
        onLayerBlendModeSelected: widget.onLayerBlendModeSelected,
      ),
      // The track's own layer, in no folder: the stack it stands in is
      // its own.
      wears: (layer: layer, stack: [layer]),
    );
  }

  /// A CONTE row's rail label, at [seat] of the track's conte group — THE
  /// TIMELINE'S OWN ROW ([TimelineLayerControlsRow]), wearing its row in
  /// hand ([projectionRowInHandOn]): the cut stood in's row at the seat,
  /// else the seat's head.
  ///
  /// 🗣️I-73 (유저 2026-10-08): 「콘티행도 동일하게 하고싶으니까 어태치
  /// 접기펼치기버튼등 동일하게 할수있는거 다 넣는거 잊지말고」 · 「콘티레이어
  /// 권고한대로 머리만 한벌 ok. 맘에드는생각이야. 겸용컷이랑 같은 느낌이네」
  /// · 「이거만 눈이랑 불투명도조차 링크하도록. 그거마저 머리로서
  /// 하나로되도록 통일」. The row is the widget the timeline's rail builds
  /// for the same layer, not a second listing of its cells, so what that
  /// row grows this one has; and every control on it writes the row in
  /// hand, whose head the commands carry to the row at this seat of every
  /// cut (`headMirrorTargets`).
  ///
  /// The head's contents are the drawn proposal's: 「이름 옆의 접기(∨)로
  /// 어태치 행을 접고, 라벨 · fx · 눈 · 불투명도 · 블렌드 · 레인 펼침이
  /// 타임라인과 같이 됩니다」. Past it, the head carries what is ONE for
  /// the track's cuts and nothing that is each cut's own (🗣️I-89-Q22, 유저
  /// 2026-10-16: 「공통으로 안되는건 애초에 콘티패널에 버튼두지않음 …
  /// 콘티행은 그런부분 글로벌이니까 아니면 글로벌시키고 넣고 머리로 하나.
  /// 어니언도 콘티행 기본적으로 버튼 글로벌이니까 넣음」): the sheet toggle,
  /// made the head's ([ConteHead.onTimesheet]), and the onion, read
  /// through the head's rows (`OnionSkin.isLayerOnionSkinEnabled`). The
  /// clip switch and the link badge are not handed here, and the
  /// row mounts neither. ↩️The sheet toggle and the onion stayed off it too
  /// until Q22 — the flag was each cut's own.
  ///
  /// A press picks the ROW ([trackConteRowId]) — never the head's layer,
  /// which is one cut's — and the session lands it on the layer at this
  /// seat of the cut it stands in.
  ///
  /// While no cut holds a row at the seat there is no head to wear, and
  /// while the host has not wired the head's verbs there is nothing for its
  /// controls to do: the row then keeps its slots reserved and empty
  /// ([_StoryboardHeadlessLabel]).
  ///
  /// It takes this rail's row grammar as the timeline's row does: a drag on
  /// it selects, and a drag inside the selection re-orders the conte group
  /// — the seat's rows in every cut — as the timeline's drag of that row
  /// does (🗣️F-322, 유저 2026-10-09: 「선택범위 드래그로 어태치 조정」 ·
  /// 「드래그로 어태치 순서이동이라던가 … 다 되도록하는거 잊지말고」). A seat
  /// no cut holds a row at has nothing to move, and selects all the same.
  Widget conteLabelRow(Track track, int seat) {
    final trackId = track.id;
    final rowId = trackConteRowId(trackId, seat: seat);
    final subject = ConteSeatRowSubject(rowId);
    final label = _conteLabelOf(track, seat);
    // Asked at the press, of the track as it stands then: the row is kept
    // while what it shows holds.
    List<DragChipItem> grip() => [
      if (_state._railRows._trackNamed(trackId) case final now?)
        (
          icon: layerKindIcon(LayerKind.storyboard),
          label: trackConteRowName(now.cuts, seat: seat),
        ),
    ];
    final hooks = _state.widget.rowDragHooks;
    final seats = _state._railRows._shownConteSeats(track);
    final index = seats.indexOf(seat);
    if (hooks == null || index < 0 || conteHeadAt(track.cuts, seat) == null) {
      final height = _state._rowHeights.conte;
      return _keptSelectOnly(label, subject, height, grip: grip);
    }
    final extent = _state._railRows._conteRowGroupExtent(track, seat);
    return _keptRow(
      ('conte', trackId, seat),
      label,
      (subject, index, seats.length, extent, _dragInputs),
      (label) => LayerRowDragTarget(
        subject: subject,
        slotBefore: index,
        rowExtent: extent,
        axis: Axis.horizontal,
        hooks: hooks,
        grip: grip,
        drawsTheGapAfter: index == seats.length - 1,
        linesBeyond: _state._railRows.linesBeyondFrom(LayerRowAddress(rowId)),
        // The timeline row's two answers: a pointer in a row's middle is ON
        // that row — the session judges what it swallows, a 공정 folder of
        // the group (I-99) — and anywhere else the caret, with the row the
        // pointer is in. ↩️It took the caret alone (「a conte group's rows
        // hold nothing to drop into」, 10-10, a rule nobody asked for).
        onCrossed: (steps, onRow, inRow) {
          final rows = _conteRowsNow(trackId);
          final from = rows.indexWhere((row) => row.id == rowId);
          if (from < 0) {
            return;
          }
          final slot = slotForSteps(from, steps, rows.length);
          final on = onRow == null ? -1 : from + onRow;
          if (on >= 0 && on < rows.length) {
            hooks.onRowTarget(rows, slot, rows[on].id);
            return;
          }
          final under = from + inRow;
          hooks.onUpdate(
            rows,
            slot,
            pointerInRow: under >= 0 && under < rows.length
                ? rows[under].id
                : null,
          );
        },
        onSelectCrossed: _spanOnSelect(),
        selectRowDeltaAt: _state._railRows.selectRowDeltaFrom(
          LayerRowAddress(rowId),
        ),
        child: label,
      ),
    );
  }

  /// The rail's conte rows of the track [trackId] as it stands at the
  /// event, by their own addresses: the session reads them as the rows of
  /// the cut the move is made in.
  List<Layer> _conteRowsNow(TrackId trackId) => [
    if (_state._railRows._trackNamed(trackId) case final track?)
      for (final seat in _state._railRows._shownConteSeats(track))
        Layer(
          id: trackConteRowId(trackId, seat: seat),
          name: '',
          frames: const [],
        ),
  ];

  /// [conteLabelRow]'s label alone, [chromeless] on the folded overlay.
  Widget _conteLabel(Track track, int seat, {bool chromeless = false}) =>
      _labelAlone(_conteLabelOf(track, seat, chromeless: chromeless));

  /// The conte row at [seat]'s label: its head, wearing its row in hand
  /// ([_conteHead]), or its slots reserved and empty.
  _RailLabel _conteLabelOf(Track track, int seat, {bool chromeless = false}) {
    final rowId = trackConteRowId(track.id, seat: seat);
    final head = projectionRowInHandOn(
      track.cuts,
      LayerRowAddress(rowId),
      standingIn: _state.widget.activeCutId,
    );
    if (head == null || !_headVerbsWired) {
      return (
        piece: _headlessLabel(
          track,
          (
            id: rowId,
            kind: LayerKind.storyboard,
            keyName: conteLabelKeyName(seat),
            name: trackConteRowName(track.cuts, seat: seat),
            height: _state._rowHeights.conte,
          ),
          chromeless: chromeless,
        ),
        wears: null,
      );
    }
    return (
      piece: _conteHead(track, seat, head, chromeless: chromeless),
      wears: (layer: head.row, stack: head.cut.layers),
    );
  }

  /// The CAMERA row's rail label (I-73 ④) — THE TIMELINE'S OWN CAMERA ROW
  /// ([TimelineLayerControlsRow]), wearing the camera layer of the cut the
  /// session stands in on this track ([_StoryboardRailRows._cameraHeadOf]).
  ///
  /// 🗣️유저 2026-10-08: 「그리고 카메라는 로컬이랑 똑같이 최상단행. cam섹션의
  /// 제일 위」 — the row the timeline shows at the top of its CAM section,
  /// shown here at the top of this one: the drawn proposal's 「머리는
  /// 타임라인의 카메라 행 머리 부품 그대로(칩 · 아이콘 · Camera · fx · 눈 ·
  /// 값)」. Everything on it is the layer's own, as the timeline's is — its
  /// eye and its slider too, the camera view's switch and its dim (F-363).
  ///
  /// The head is the cut stood in's camera, as the timeline's is. 🗣️유저
  /// 2026-10-09 (I-73-camera-row-Q1): its name, its fx switch, its eye and
  /// its opacity are ONE for the track's cuts, its colour label each cut's
  /// own — the commands carry them to every camera of the track
  /// (`cameraHeadTargets`).
  ///
  /// A press picks the ROW ([trackCameraRowId]) — never the head's layer —
  /// and the session lands it on the camera layer of the cut it stands in.
  /// In a gap there is no head to wear: the row keeps its slots reserved and
  /// empty ([_StoryboardHeadlessLabel]).
  Widget cameraLabelRow(Track track) {
    final trackId = track.id;
    return _keptSelectOnly(
      _cameraLabelOf(track),
      LayerRowSubject(trackCameraRowId(trackId)),
      _state._rowHeights.camera,
      // Asked at the press, of the track as it stands then: the row is kept
      // while what it shows holds.
      grip: () => [
        if (_state._railRows._trackNamed(trackId) case final now?)
          (
            icon: layerKindIcon(LayerKind.camera),
            label: trackCameraRowName(
              now.cuts,
              standingIn: _state.widget.activeCutId,
            ),
          ),
      ],
    );
  }

  /// [cameraLabelRow]'s label alone, [chromeless] on the folded overlay.
  Widget _cameraLabel(Track track, {bool chromeless = false}) =>
      _labelAlone(_cameraLabelOf(track, chromeless: chromeless));

  /// The camera row's label: its head, wearing the camera in hand, or its
  /// slots reserved and empty.
  _RailLabel _cameraLabelOf(Track track, {bool chromeless = false}) {
    final head = _state._railRows._cameraHeadAt(track);
    if (head == null || !_headVerbsWired) {
      return (
        piece: _cameraHeadless(track, chromeless: chromeless),
        wears: null,
      );
    }
    final widget = _state.widget;
    final rowId = trackCameraRowId(track.id);
    final trackId = track.id;
    final graphKey = laneGraphHeadedBy(head.layer, null);
    return (
      piece: _StoryboardRailHead(
        key: ValueKey<String>('storyboard-camera-label-${trackId.value}'),
        rowId: rowId,
        chromeless: chromeless,
        layer: head.layer,
        active: widget.selectedRow == LayerRowAddress(rowId),
        // Its twirl — the timeline's camera row's — opens the row's lanes
        // under it (I-73 ④ⓔ): the camera's, which every camera has.
        hasLanes: true,
        lanesExpanded: _state._railRows._cameraLanesOpen(track),
        onToggleLanes: _twirlTurning(
          () => switch (_state._railRows._trackNamed(trackId)) {
            final now? => _state._railRows._cameraTwirlOf(now),
            null => null,
          },
        ),
        metrics: _headMetrics(_state._rowHeights.camera),
        onSelectLayer: widget.onSelectLayer,
        onSettledPress: widget.onSettledPress,
        labelDoubleClick: widget.labelDoubleClick,
        onToggleLayerVisibility: widget.onToggleLayerVisibility,
        onLayerOpacityChanged: widget.onLayerOpacityChanged,
        onLayerOpacityChangeEnd: widget.onLayerOpacityChangeEnd,
        opacityDragPreview: widget.opacityDragPreview,
        onLayerMarkSelected: widget.onLayerMarkSelected,
        onToggleLayerTimesheet: _sheetToggleOf(rowId),
        // This rail has the blend column, as the conte heads say: a camera
        // keeps its slot empty, so the columns stand over the rows' own.
        onLayerBlendModeSelected: widget.onLayerBlendModeSelected,
        fxState: widget.layerFxStateOf?.call(head.layer.id) ?? LayerFxState.on,
        onToggleLayerFx: widget.onToggleLayerFx,
        onOpenCameraPath: widget.onOpenCameraPath,
        // I-89 ①: the timeline camera row's graph button — on the camera
        // in hand, whose head family the session turns as one.
        laneGraphVerbs: _state._railRows._laneGraphVerbs,
        headsGraph: graphKey != null,
        graphOpen:
            graphKey != null &&
            _state._railRows._laneGraphs.open.containsKey(graphKey),
      ),
      wears: (layer: head.layer, stack: head.cut.layers),
    );
  }

  /// The camera row's slots reserved and empty — in a gap, or while the
  /// host has not wired the head's verbs — under the name the row goes by.
  _StoryboardHeadlessLabel _cameraHeadless(
    Track track, {
    required bool chromeless,
  }) => _headlessLabel(
    track,
    (
      id: trackCameraRowId(track.id),
      kind: LayerKind.camera,
      keyName: 'camera',
      name: trackCameraRowName(
        track.cuts,
        standingIn: _state.widget.activeCutId,
      ),
      height: _state._rowHeights.camera,
    ),
    chromeless: chromeless,
  );

  /// A PROJECTION row's label while it has no head to wear, or the host has
  /// not wired the head's verbs: its slots reserved and empty
  /// ([_StoryboardHeadlessLabel]), stood on by [row]'s own address.
  _StoryboardHeadlessLabel _headlessLabel(
    Track track,
    ({
      LayerId id,
      LayerKind kind,
      String keyName,
      String name,
      double height,
    })
    row, {
    bool chromeless = false,
  }) => _StoryboardHeadlessLabel(
    chromeless: chromeless,
    trackId: track.id,
    rowId: row.id,
    kind: row.kind,
    keyName: row.keyName,
    name: row.name,
    active: _state.widget.selectedRow == LayerRowAddress(row.id),
    height: row.height,
    onSelectLayer: _state.widget.onSelectLayer,
    onSettledPress: _state.widget.onSettledPress,
  );

  /// Whether the host wired the verbs a head that is the timeline's own row
  /// cannot stand without — its eye, its opacity, its label and its blend,
  /// which that row takes as given ([_StoryboardRailHead]).
  bool get _headVerbsWired {
    final widget = _state.widget;
    return widget.onToggleLayerVisibility != null &&
        widget.onLayerOpacityChanged != null &&
        widget.onLayerMarkSelected != null &&
        widget.onLayerBlendModeSelected != null;
  }

  /// The sheet toggle the head of [rowId]'s row is handed: the host's,
  /// where the row is handed one at all — the rule the column sweep paints
  /// by too ([_StoryboardRailSweep.handsSheetToggle]).
  ValueChanged<LayerId>? _sheetToggleOf(LayerId rowId) =>
      _state._sweep.handsSheetToggle(rowId)
      ? _state.widget.onToggleLayerTimesheet
      : null;

  /// The metrics a head is laid out at: this rail's width, [rowHeight].
  TimelineGridMetrics _headMetrics(double rowHeight) =>
      TimelineGridMetrics.defaults.copyWith(
        layerControlsWidth: _state._naturalRailWidth,
        layerRowHeight: rowHeight,
        railColumns: layerRailColumnWidthsIn(_state.context),
      );

  /// [row] — a head's, alone or in the wrapper its rail row puts on it —
  /// wearing [wears]' layer: the one its row has in hand NOW, which a kept
  /// head may have been built for another of ([BerthRow]). Its eye shows
  /// that layer's, as the folders of [wears]' stack gate it ([RailEyes]) —
  /// the timeline rail's own answer for the layer (F-185).
  Widget _wearing(({Layer layer, List<Layer> stack}) wears, Widget row) =>
      RailEyes.forLayers(
        [wears.layer],
        stack: wears.stack,
        child: BerthRow(layer: wears.layer, child: row),
      );

  /// [head]'s row as the timeline's rail builds it, at this rail's width
  /// and the conte rows' height — standing for [seat] of [track]: lit when
  /// that row is the one stood on, and picking THAT row when pressed.
  _StoryboardRailHead _conteHead(
    Track track,
    int seat,
    ({Cut cut, Layer row}) head, {
    bool chromeless = false,
  }) {
    final widget = _state.widget;
    final rowId = trackConteRowId(track.id, seat: seat);
    final trackId = track.id;
    final fold = _state._railRows._conteGroupFoldOf(rowId);
    return _StoryboardRailHead(
      key: ValueKey<String>(
        'storyboard-${conteLabelKeyName(seat)}-label-${trackId.value}',
      ),
      rowId: rowId,
      chromeless: chromeless,
      // Hung off the conte as the timeline hangs the group off its base:
      // one level per 공정 folder above the row (I-99).
      depth: attachFolderLevelsAbove(head.row, head.cut.layers),
      layer: head.row,
      active: widget.selectedRow == LayerRowAddress(rowId),
      // Its twirl — the timeline row's — opens the row's lanes under it
      // (I-73 ④ⓔ), the rows at its seat in every cut as one; a row riding
      // the conte opens its own (I-99), as on the timeline.
      hasLanes: _state._railRows._conteLanes(track, seat).isNotEmpty,
      lanesExpanded: _state._railRows._conteLanesOpen(track, seat),
      onToggleLanes: _twirlTurning(
        () => switch (_state._railRows._trackNamed(trackId)) {
          final now? => _state._railRows._conteTwirlOf(now, seat),
          null => null,
        },
      ),
      metrics: _headMetrics(_state._rowHeights.conte),
      onSelectLayer: widget.onSelectLayer,
      onSettledPress: widget.onSettledPress,
      labelDoubleClick: widget.labelDoubleClick,
      onToggleLayerVisibility: widget.onToggleLayerVisibility,
      onLayerOpacityChanged: widget.onLayerOpacityChanged,
      onLayerOpacityChangeEnd: widget.onLayerOpacityChangeEnd,
      opacityDragPreview: widget.opacityDragPreview,
      onLayerMarkSelected: widget.onLayerMarkSelected,
      onToggleLayerTimesheet: _sheetToggleOf(rowId),
      onToggleLayerOnionSkin: widget.onToggleLayerOnionSkin,
      onionSkinEnabled:
          widget.layerOnionSkinEnabledOf?.call(head.row.id) ?? false,
      fxState: widget.layerFxStateOf?.call(head.row.id) ?? LayerFxState.on,
      onToggleLayerFx: widget.onToggleLayerFx,
      onLayerBlendModeSelected: widget.onLayerBlendModeSelected,
      // An attach row says which side of its base it rides, and wears the
      // base's composite — the timeline row's own two answers, asked of
      // the stack the head stands in.
      attachArrowPlacement: attachArrowPlacement(head.row, head.cut.layers),
      wearsBaseComposite: attachRowWearsBaseComposite(
        head.row,
        head.cut.layers,
      ),
      hasGroupFold: fold.has,
      groupFoldExpanded: fold.expanded,
      onToggleGroupFold: fold.onToggle,
    );
  }

  /// A projection row's lane twirl, as its head presses it (I-73 ④ⓔ): the
  /// timeline's twirl, turned through the row [which] names — the one its
  /// rows turn as one by — or null while the host takes no twirl.
  ValueChanged<LayerId>? _twirlTurning(LayerId? Function() which) {
    final toggle = _state.widget.onToggleLayerLanes;
    return toggle == null
        ? null
        : (_) {
            final row = which();
            if (row != null) {
              toggle(row);
            }
          };
  }

  /// The word a conte row's label is keyed by: `conte` for the conte
  /// itself, and its seat after it for an attach row (`conte+1`, `conte-1`).
  static String conteLabelKeyName(int seat) =>
      seat == 0 ? 'conte' : 'conte${seat > 0 ? '+' : ''}$seat';

  /// The transition row's strip: the track's spans on the GLOBAL axis, live
  /// through the session's edge-drag form while a grip is held.
  Widget transitionStripRow(Track track, double width, TimelineScale scale) {
    final committed = track.transitionLayer;
    final height = _state._rowHeights.transition;
    Widget row(Layer layer) => _StoryboardTransitionRow(
      trackId: track.id,
      layer: _state.widget.transitionRowShown?.call(track, layer) ?? layer,
      width: width,
      height: height,
      timelineScale: scale,
      frameGeometry: _state._frameGeometry,
      windowBucket: _state._horizontalWindowBucket,
      showSeconds: _state.widget.showSeconds,
      projectFrameRate: _state.widget.projectFrameRate,
      defById: _state.widget.transitionDefById,
      crossingTooltip: _state.widget.transitionCrossingTooltip,
      commaDrag: _state.widget.transitionCommaDrag,
      onRowFramePress: _state.widget.onRowFramePress,
      onEditSpan: _state.widget.onEditTransitionSpan,
      // The SE rows' selection bundle, unchanged: one rail, one range verb.
      select: _state.widget.seSelect,
      railSweepAt: _state._railRows._railSweepOn(track.id),
    );
    // The SE strips' gate, as is: a grip or a move publishes the row's two
    // forms on the one channel, and this strip — the track axis — draws the
    // GLOBAL one while the cut's rows draw the projection.
    return TimelineDragPreviewRowGate(
      dragPreview: _state.widget.dragPreview,
      layer: committed,
      useGlobalForm: true,
      rowBuilder: (context, layer) => row(layer),
    );
  }

  /// [seLabelRow]'s label alone, [chromeless] on the folded overlay — its
  /// height and nothing on it where the slot holds no row, which no slot
  /// the rail shows does ([_StoryboardRailRows._shownSeSlots]).
  Widget _seLabel(Track track, int slot, {bool chromeless = false}) =>
      switch (_trackSeAt(track, slot)) {
        final layer? => _labelAlone(
          _seLabelOf(track, slot, layer, chromeless: chromeless),
        ),
        null => SizedBox(height: _state._rowHeights.se),
      };

  /// The S row at [slot] of [track], [layer]'s: THE TIMELINE'S OWN ROW
  /// for the SE row ([_StoryboardRailHead]) — the row the timeline shows
  /// for the same layer, so its sheet toggle (B5③ 2026-08-17, superseding
  /// UI-R9 #5's empty slot — ordered twice: the flag is a LAYER field and
  /// the row's layer is track-owned, so it needs no cut to act), its
  /// speaker opening the row's mixer (R10 R3), and no waveform-hide eye
  /// (UI-R7 #8 — ↩️said while the twirled-down Audio lane was the big
  /// waveform; the lane went with I-140).
  ///
  /// The controls belong to the ROW, and the row belongs to the track: a
  /// gap kept them up already (UI-R10 #12, "the SE rows are TRACK-owned"),
  /// and the active cut living on ANOTHER track is the same statement, so
  /// it gets the same answer (user, 2026-08-09).
  _RailLabel _seLabelOf(
    Track track,
    int slot,
    Layer layer, {
    bool chromeless = false,
  }) {
    final widget = _state.widget;
    return (
      piece: _StoryboardRailHead(
        key: ValueKey<String>(
          'storyboard-se-label-${track.id.value}-${slot + 1}',
        ),
        rowId: layer.id,
        chromeless: chromeless,
        layer: layer,
        active: widget.selectedRow == LayerRowAddress(layer.id),
        fxState: widget.layerFxStateOf?.call(layer.id) ?? LayerFxState.on,
        metrics: _headMetrics(_state._rowHeights.se),
        // The twirl is the SE row's own (F-360), the timeline's — pressed
        // with the row the label stands for at the press ([BerthRow]).
        hasLanes: _state._railRows._seLanes(track, slot).isNotEmpty,
        lanesExpanded: _state._railRows._seLanesOpen(track, slot),
        onToggleLanes: widget.onToggleLayerLanes,
        onSelectLayer: widget.onSelectLayer,
        onSettledPress: widget.onSettledPress,
        labelDoubleClick: widget.labelDoubleClick,
        onToggleLayerVisibility: widget.onToggleLayerVisibility,
        onLayerOpacityChanged: widget.onLayerOpacityChanged,
        onLayerOpacityChangeEnd: widget.onLayerOpacityChangeEnd,
        opacityDragPreview: widget.opacityDragPreview,
        onLayerMarkSelected: widget.onLayerMarkSelected,
        onToggleLayerTimesheet: _sheetToggleOf(layer.id),
        onOpenLayerMixer: widget.onOpenLayerMixer,
        soloed: widget.isLayerSoloed?.call(layer.id) ?? false,
        onToggleLayerFx: widget.onToggleLayerFx,
        // This rail has the blend column: an S row keeps its slot empty, so
        // its columns stand over every other row's — the sweep's bands
        // included ([StoryboardPanel.optionalRailColumns]).
        onLayerBlendModeSelected: widget.onLayerBlendModeSelected,
      ),
      // The track's own row, in no folder: its eye is its own.
      wears: (layer: layer, stack: track.seLayers),
    );
  }

  /// The V row, made draggable to re-order the project's TRACKS (R5 #9).
  ///
  /// The rail lists tracks in the project's own order (the caller walks
  /// `project.tracks` forward), so the row index IS the slot before it and
  /// nothing has to be reversed the way the S rows' list does.
  ///
  /// ⚠️ The pitch is THIS group's height, so tracks of differing heights
  /// drift after the first step — the same limitation the S rows have when
  /// their lanes are open, and the same fix (a per-row extent list on the
  /// shared drag widget) would close both.
  ///
  /// The row's lane splitter rides it, kept with it.
  Widget trackDraggable(Track track, int index, KeptPiece label) {
    final trackId = track.id;
    final hooks = _state.widget.rowDragHooks;
    final trackCount = _state.widget.project.tracks.length;
    final subject = TrackRowSubject(trackId);
    final extent = _state._railRows._trackGroupExtent(track);
    final resizable = _state.widget.onResizeTrackLanes != null;
    List<DragChipItem> grip() => [
      (icon: _vRowGlyph, label: storyboardVideoRowName(index)),
    ];
    Widget split(Widget row) =>
        _state._railRows._withTrackLaneSplitter(trackId, row);
    if (hooks == null || hooks.onTrackUpdate == null || trackCount < 2) {
      // One track cannot be re-ordered, and a rail with no hooks is
      // display-only — and the row SELECTS all the same (F-322; 08-29:
      // 「v행트랙이든 뭐든 선택범위는 작동하게」). ↩️It stayed a plain label.
      return _keptRow(
        ('v', trackId),
        (piece: label, wears: null),
        (_selectOnlyInputs(subject, extent), index, resizable),
        (label) => split(selectOnly(subject, extent, label, grip: grip)),
      );
    }
    final grabOffset = _state._railRows._trackGroupExtentAboveVRow(track);
    return _keptRow(
      ('v', trackId),
      (piece: label, wears: null),
      (subject, index, trackCount, extent, grabOffset, _dragInputs, resizable),
      (label) => split(
        LayerRowDragTarget(
          subject: subject,
          slotBefore: index,
          rowExtent: extent,
          // ④: the handle is the V row, the pitch is the whole group — so
          // the drag is told how far into the group the handle starts.
          grabOffsetWithinRun: grabOffset,
          axis: Axis.horizontal,
          hooks: hooks,
          grip: grip,
          drawsTheGapAfter: index == trackCount - 1,
          linesBeyond: _state._railRows.linesBeyondFrom(
            TrackRowAddress(trackId),
          ),
          // A track holds nothing, so its middle means nothing: the caret
          // is the only answer and the on-row arm stays unused (the S rows'
          // reasoning, one list up).
          onCrossed: (steps, _, _) =>
              hooks.onTrackUpdate!(slotForSteps(index, steps, trackCount)),
          onSelectCrossed: _spanOnSelect(),
          selectRowDeltaAt: _state._railRows.selectRowDeltaFrom(
            TrackRowAddress(trackId),
          ),
          child: label,
        ),
      ),
    );
  }
}

/// A rail row's label as [_StoryboardRowsAndLabels._keptRow] keeps it: the
/// [piece] it shows, and — a head's — the layer its row has in hand and the
/// stack it stands in, which the head [wears] past its keep.
typedef _RailLabel = ({
  KeptPiece piece,
  ({Layer layer, List<Layer> stack})? wears,
});

/// What the rail keeps of its rows (F-244): each row — its label in the
/// drag wrapper put on it — held as built while the label's facts and what
/// the wrapper is built from hold. A row's address stands through a cut
/// crossed, so its wrapper and its label are kept as one; the timeline's
/// rail keeps the two apart (`KeptLayerControlsRows`) because its berths
/// change address under a kept row.
///
/// 🚨I-57 (10-14): every wrapper was built again with the panel on every
/// notify and every cut crossed — 🔬64 of a crossing's 330 rebuilds on the
/// AMMI OP, each row's gesture layer among them.
///
/// It holds the rows of the latest PASS ([pass]) and no others: a row the
/// rail stops drawing lets go of what it was built from (I-57 ㉣: a memo
/// that let go of nothing held every layer of every cut it had shown).
final class _KeptRailRows {
  Map<Object, Kept<Object?>> _held = {};
  Map<Object, Kept<Object?>> _before = {};

  /// [build]'s rows, kept as one pass.
  List<Widget> pass(List<Widget> Function() build) {
    _before = _held;
    _held = {};
    try {
      return build();
    } finally {
      _before = {};
    }
  }

  /// The row held for [key] while [facts] are what it was built from, else
  /// [build]'s, held.
  Widget keep(Object key, Object? facts, Widget Function() build) {
    if (_before.remove(key) case final kept?) {
      _held[key] = kept;
    }
    return keptWhileSame(_held, key, facts, build);
  }
}

/// A V row's glyph — what its label row shows beside its name
/// ([storyboardVideoRowName]), and what its chip shows once the row is
/// picked up (I-39).
const IconData _vRowGlyph = Icons.movie_outlined;
