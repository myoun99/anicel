import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../repaint_props.dart';
import '../text/app_strings.dart' show AppText;
import '../text/text_measure.dart';
import '../theme/app_theme.dart';
import '../theme/disabled_ink.dart';
import 'app_icon_button.dart';
import 'drag_value_label.dart';
import 'field_slider.dart';
import 'owning_axis_grip.dart';

/// The span a surface that TRIMS keeps of its source — the transport's third
/// row.
class TransportRange {
  const TransportRange({
    required this.inFrame,
    required this.outFrame,
    required this.onChanged,
  });

  /// ZERO-based, inside the source, IN never past OUT.
  final int inFrame;
  final int outFrame;

  /// A new (in, out) pair, already ordered and inside the source.
  ///
  /// Null while the span can act on nothing — a source with one frame, a
  /// file the import adds nothing of. The row stays where it is, and is
  /// off: a row that came and went with the file picked would move the
  /// picture above it.
  final void Function(int inFrame, int outFrame)? onChanged;
}

/// How loud the thing playing is — the transport's sound cell.
class TransportSound {
  const TransportSound({
    required this.level,
    required this.muted,
    required this.onLevelChanged,
    required this.onLevelSettled,
    required this.onMuteToggled,
  });

  /// 0..1.
  final double level;
  final bool muted;

  /// Every step of the bar under the hand, and once where the hand lets go
  /// — a surface whose sound is armed at a level arms it again on the
  /// second.
  final ValueChanged<double> onLevelChanged;
  final ValueChanged<double> onLevelSettled;
  final VoidCallback onMuteToggled;
}

/// THE transport: what stands under anything that runs in time — the import
/// window's preview, the media viewer panel, and the export window's.
///
/// 🗣️F-289 (유저 2026-10-06): 「미디어플레이어처럼 재생바를 위에,
/// 재생버튼관련을 아래에 해서 2줄로 나누고싶어. 윗줄은 최대한 재생바
/// 크게하고싶으니 재생바로 꽉 채우고, 아래줄에 재생관련버튼+사운드
/// 조절버튼. 그리고 인아웃은 지금처럼 해서 3번째 줄로서 등록」. So, top to
/// bottom:
///
///  1. the seek track, as wide as the surface;
///  2. where the playhead stands, the player's buttons in the middle, and
///     the sound;
///  3. IN and OUT — on a surface that trims, and only there ([range];
///     「IN OUT 지정은 진짜 임포트/익스포트에서만 쓰니까 쓰는곳에서만
///     보이도록」).
///
/// ↩️It was ONE track carrying the playhead and both handles, with the range
/// readouts at the ends of the button row and the position under it.
///
/// It never learns what is behind the frames: it takes a COUNT and an index
/// and reports what the hand did. A source with one frame mounts it too —
/// every control stays where it is, and none of them can go anywhere
/// (「이미지처럼 대응불가하면 비활성화 해두는정도」).
class TransportBar extends StatelessWidget {
  const TransportBar({
    super.key,
    required this.frameCount,
    required this.currentFrame,
    required this.playing,
    required this.onSeek,
    required this.onPlayPause,
    this.range,
    this.sound,
    this.keyPrefix = 'transport',
  });

  /// How many frames the source has. One means a still: every control
  /// still renders, and none of them can go anywhere.
  final int frameCount;

  /// A ZERO-based index. The readout adds one, because a person counts
  /// pages and frames from one.
  final int currentFrame;

  final bool playing;
  final ValueChanged<int> onSeek;

  /// Null when there is nothing to play — a still, a PDF: the button stays
  /// where it is and is off.
  final VoidCallback? onPlayPause;

  /// The span IN/OUT keep, or null on a surface that does not trim — it has
  /// no third row.
  final TransportRange? range;

  /// The sound beside the frames, or null when nothing here makes any: the
  /// cell stays where it is and is off.
  final TransportSound? sound;

  /// What every widget key in the bar is built from. A surface that can be
  /// mounted twice at once — the two media viewers — names its own.
  final String keyPrefix;

  /// The narrowest the bar lays out with its range shown: the IN and OUT
  /// readouts keep their width at either end of the row, and the track
  /// between them is what gives.
  static const double minimumWidth = 2 * (_rangeEndWidth + _gap + _inset);

  /// The wash over the span IN/OUT keep — the tracks', and wherever the
  /// same span is marked over the source itself (the import preview's
  /// waveform).
  static Color get rangeWash => AppColors.accent.withValues(alpha: 0.18);

  /// The bar where it is shown, with or without the range row — its rows at
  /// 1× and one line of their words grown under the OS text size
  /// (text-scale-fixed-height-bars).
  static double heightIn(BuildContext context, {required bool range}) {
    final growth = _lineGrowthIn(context);
    return _seekRowHeight +
        _playRowHeight +
        growth +
        (range ? _rangeRowHeight + growth : 0);
  }

  static const double _inset = 8;
  static const double _gap = 8;
  static const double _seekRowHeight = 25;
  static const double _playRowHeight = 28;

  /// The row and the hairline over it.
  static const double _rangeRowHeight = 27;
  static const double _rangeEndWidth = 76;
  static const double _volumeWidth = 64;
  static const double _volumeHeight = 18;

  static double _lineGrowthIn(BuildContext context) => TextMeasure(
    context,
    Theme.of(context).textTheme.labelSmall ?? const TextStyle(),
  ).lineGrowthOf(TextMeasure.everyScript);

  int get _lastFrame => frameCount <= 1 ? 0 : frameCount - 1;

  int _clamp(int frame) =>
      frame < 0 ? 0 : (frame > _lastFrame ? _lastFrame : frame);

  String _key(String suffix) => '$keyPrefix-$suffix';

  @override
  Widget build(BuildContext context) {
    final digits = '$frameCount'.length;
    String label(int frame) => '${frame + 1}'.padLeft(digits, '0');
    final range = this.range;
    // A span that can act: it is washed on the seek track, and the end
    // buttons stop at it.
    final kept = range != null && range.onChanged != null ? range : null;
    final growth = _lineGrowthIn(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(_inset, 7, _inset, 4),
          child: TransportTrack(
            keyValue: _key('track'),
            frameCount: frameCount,
            currentFrame: currentFrame,
            kept: kept == null
                ? null
                : (first: kept.inFrame, last: kept.outFrame),
            onSeek: onSeek,
          ),
        ),
        SizedBox(
          height: _playRowHeight + growth,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(_inset, 0, _inset, 4),
            child: CustomMultiChildLayout(
              delegate: _PlayRowLayout(),
              children: [
                LayoutId(
                  id: _PlaySlot.readout,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${label(currentFrame)} / $frameCount',
                      key: ValueKey<String>(_key('position')),
                      style: _wordsIn(context, enabled: _lastFrame > 0),
                    ),
                  ),
                ),
                LayoutId(
                  id: _PlaySlot.buttons,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _buttons(kept),
                  ),
                ),
                LayoutId(
                  id: _PlaySlot.sound,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _soundCell(context, growth),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (range != null) ...[
          const SizedBox(
            height: 1,
            child: ColoredBox(color: AppColors.hairline),
          ),
          SizedBox(
            height: _rangeRowHeight - 1 + growth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _inset),
              child: _rangeRow(context, range, label),
            ),
          ),
        ],
      ],
    );
  }

  /// First, back one, play, on one, last. The ends stop at IN and OUT where
  /// a span is kept — that span is what runs.
  Widget _buttons(TransportRange? kept) {
    final strings = AppText.strings;
    final canMove = _lastFrame > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconButton(
          keyValue: _key('first'),
          tooltip: kept == null
              ? strings.transportToStart
              : strings.transportIn,
          icon: const Icon(Icons.first_page),
          size: AppIconButtonSize.strip,
          onPressed: canMove ? () => onSeek(kept?.inFrame ?? 0) : null,
        ),
        AppIconButton(
          keyValue: _key('step-back'),
          tooltip: strings.transportPrevFrame,
          icon: const Icon(Icons.chevron_left),
          size: AppIconButtonSize.strip,
          onPressed: canMove ? () => onSeek(_clamp(currentFrame - 1)) : null,
        ),
        AppIconButton(
          keyValue: _key('play'),
          tooltip: playing ? strings.menuPause : strings.menuPlay,
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          size: AppIconButtonSize.bar,
          isSelected: playing,
          onPressed: onPlayPause,
        ),
        AppIconButton(
          keyValue: _key('step-forward'),
          tooltip: strings.transportNextFrame,
          icon: const Icon(Icons.chevron_right),
          size: AppIconButtonSize.strip,
          onPressed: canMove ? () => onSeek(_clamp(currentFrame + 1)) : null,
        ),
        AppIconButton(
          keyValue: _key('last'),
          tooltip: kept == null ? strings.transportToEnd : strings.transportOut,
          icon: const Icon(Icons.last_page),
          size: AppIconButtonSize.strip,
          onPressed: canMove
              ? () => onSeek(kept?.outFrame ?? _lastFrame)
              : null,
        ),
      ],
    );
  }

  /// The speaker and the level beside it.
  ///
  /// The bar is the app's one value bar, in its micro form — the number
  /// alone, as the rail's opacity bars write theirs. Muted, it stands grey
  /// and is still the level a press of the speaker comes back to.
  Widget _soundCell(BuildContext context, double growth) {
    final sound = this.sound;
    final muted = sound?.muted ?? false;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconButton(
          keyValue: _key('mute'),
          tooltip: AppText.strings.audioMute,
          icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
          size: AppIconButtonSize.strip,
          onPressed: sound?.onMuteToggled,
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: _volumeWidth,
          child: FieldSlider(
            key: ValueKey<String>(_key('volume')),
            value: (sound?.level ?? 1).clamp(0.0, 1.0).toDouble(),
            min: 0,
            max: 1,
            divisions: 100,
            displayScale: 100,
            height: _volumeHeight + growth,
            restingAccent: muted ? AppColors.textDim : null,
            onChanged: sound?.onLevelChanged,
            onChangeEnd: sound?.onLevelSettled,
          ),
        ),
      ],
    );
  }

  /// IN and its number, the span between the two handles, OUT's number and
  /// OUT.
  Widget _rangeRow(
    BuildContext context,
    TransportRange range,
    String Function(int frame) label,
  ) {
    final strings = AppText.strings;
    final live = range.onChanged != null;
    final words = _wordsIn(context, enabled: live);
    DragValueLabel value(
      String suffix,
      int frame,
      void Function(int frame) set,
    ) => DragValueLabel(
      keyValue: _key(suffix),
      text: label(frame),
      width: 44,
      unitsPerPixel: 1,
      enabled: live,
      onDragDelta: (delta) => set(frame + delta.round()),
      onEditSubmit: (text) {
        final typed = int.tryParse(text.trim());
        if (typed != null) {
          set(typed - 1);
        }
      },
    );
    Widget end(Alignment alignment, List<Widget> children) => SizedBox(
      width: _rangeEndWidth,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
    return Row(
      children: [
        end(Alignment.centerLeft, [
          Text(strings.transportIn, style: words),
          const SizedBox(width: 4),
          value('in', range.inFrame, _setIn),
        ]),
        const SizedBox(width: _gap),
        Expanded(
          child: TransportRangeTrack(
            keyValue: _key('range'),
            frameCount: frameCount,
            inFrame: range.inFrame,
            outFrame: range.outFrame,
            onChanged: range.onChanged,
          ),
        ),
        const SizedBox(width: _gap),
        end(Alignment.centerRight, [
          value('out', range.outFrame, _setOut),
          const SizedBox(width: 4),
          Text(strings.transportOut, style: words),
        ]),
      ],
    );
  }

  /// IN never passes OUT, and a typed value that would is pulled back to
  /// it rather than refused: the field's contract everywhere in this app is
  /// that it takes what you typed and lands on the nearest legal value.
  void _setIn(int frame) {
    final range = this.range!;
    final next = _clamp(frame);
    range.onChanged?.call(
      next > range.outFrame ? range.outFrame : next,
      range.outFrame,
    );
  }

  void _setOut(int frame) {
    final range = this.range!;
    final next = _clamp(frame);
    range.onChanged?.call(
      range.inFrame,
      next < range.inFrame ? range.inFrame : next,
    );
  }

  /// The bar's words — set solid, so a counting readout does not shiver —
  /// in the dim ink, or that ink off.
  TextStyle? _wordsIn(BuildContext context, {required bool enabled}) =>
      Theme.of(context).textTheme.labelSmall?.copyWith(
        color: dimmedIfDisabled(AppColors.textDim, enabled: enabled),
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

enum _PlaySlot { readout, buttons, sound }

/// The play row: the buttons hold the middle at their own width, and the
/// readout and the sound share what is left on either side — each scaled
/// down inside its share rather than run over (they sit in a [FittedBox]).
///
/// ⚠️A delegate, not a [LayoutBuilder]: the row is sized while it is laid
/// out, so nothing is built again to learn a width (the panel law — a
/// builder lays itself out again on every rebuild).
class _PlayRowLayout extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    final buttons = layoutChild(_PlaySlot.buttons, BoxConstraints.loose(size));
    final side = BoxConstraints.loose(
      Size(
        math.max(0.0, (size.width - buttons.width) / 2 - TransportBar._gap),
        size.height,
      ),
    );
    final readout = layoutChild(_PlaySlot.readout, side);
    final sound = layoutChild(_PlaySlot.sound, side);
    double middle(Size child) => (size.height - child.height) / 2;
    positionChild(_PlaySlot.readout, Offset(0, middle(readout)));
    positionChild(
      _PlaySlot.buttons,
      Offset((size.width - buttons.width) / 2, middle(buttons)),
    );
    positionChild(
      _PlaySlot.sound,
      Offset(size.width - sound.width, middle(sound)),
    );
  }

  @override
  bool shouldRelayout(_PlayRowLayout oldDelegate) => false;
}

/// The frame under [x] on a track [width] wide that runs over
/// `0..lastFrame`.
int _frameAt(double x, double width, int lastFrame) {
  if (width <= 0 || lastFrame == 0) {
    return 0;
  }
  final frame = (x / width * lastFrame).round();
  return frame < 0 ? 0 : (frame > lastFrame ? lastFrame : frame);
}

/// How far along `0..lastFrame` [frame] stands, 0..1.
double _fractionOf(int frame, int lastFrame) =>
    lastFrame == 0 ? 0 : frame / lastFrame;

/// A track's ground: the well and the hairline round it.
void _paintTrackGround(Canvas canvas, Size size, {required bool enabled}) {
  final track = Offset.zero & size;
  canvas.drawRect(
    track,
    Paint()..color = dimmedIfDisabled(AppColors.washUp, enabled: enabled),
  );
  canvas.drawRect(
    track.deflate(0.5),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = dimmedIfDisabled(AppColors.hairline, enabled: enabled),
  );
}

/// A hairline standing on a track at [x], a little past it above and below
/// — the playhead, and each of the range's handles.
void _paintMarker(Canvas canvas, Size size, double x, Color color) {
  canvas.drawRect(
    Rect.fromLTWH(x, -3, 1, size.height + 6),
    Paint()..color = color,
  );
}

/// A track's grip: the press is reported the moment it lands and every move
/// after it, each as where along the track it is and how wide the track
/// stands.
///
/// A scrub track has to move on the press itself. A stock drag recognizer
/// would hold the first ~18px of every scrub waiting to see whether this is
/// a drag — so the press reports from `onDown` and the drag takes the arena
/// on its first movement.
///
/// F-200: and a press on the track is the track's — the grip every drag
/// verb on a control wears (the claim, and that owning drag), so no
/// scroller around it gets there first. ↩️It was a raw [Listener], which
/// takes no part in the arena and so held nothing.
///
/// ⚠️The width is asked of the box when a pointer arrives. ↩️A
/// [LayoutBuilder] stood here to learn it, and laid the track out again on
/// every tick of a run.
class _TrackGrip extends StatelessWidget {
  const _TrackGrip({
    required this.keyValue,
    required this.height,
    required this.painter,
    required this.onPress,
    required this.onMove,
  });

  final String keyValue;
  final double height;
  final CustomPainter painter;
  final void Function(double x, double width) onPress;
  final void Function(double x, double width) onMove;

  @override
  Widget build(BuildContext context) {
    void at(Offset local, void Function(double x, double width) report) =>
        report(local.dx, context.size?.width ?? 0);
    return OwningAxisGrip(
      key: ValueKey<String>(keyValue),
      axis: Axis.horizontal,
      configure: (recognizer) {
        recognizer.onDown = (details) => at(details.localPosition, onPress);
        recognizer.onStart = (details) => at(details.localPosition, onMove);
        recognizer.onUpdate = (details) => at(details.localPosition, onMove);
      },
      child: CustomPaint(painter: painter, child: SizedBox(height: height)),
    );
  }
}

/// The seek track: a press seeks there, and keeps seeking while the finger
/// moves.
///
/// A source with one frame has nowhere to seek to: the track stands, off,
/// and a press on it is still its own.
class TransportTrack extends StatefulWidget {
  const TransportTrack({
    super.key,
    required this.frameCount,
    required this.currentFrame,
    required this.onSeek,
    this.kept,
    this.keyValue = 'transport-track',
    this.height = 14,
  });

  final int frameCount;
  final int currentFrame;
  final ValueChanged<int> onSeek;

  /// The span washed on the track, or null where none is kept. The handles
  /// that move it are the range row's ([TransportRangeTrack]).
  final ({int first, int last})? kept;

  final String keyValue;
  final double height;

  @override
  State<TransportTrack> createState() => _TransportTrackState();
}

class _TransportTrackState extends State<TransportTrack> {
  /// The frame this press last reported. A press that never moves is
  /// still a drag the arena starts on the release (it is alone there), and
  /// that start lands where the press already did — reported once, the way
  /// the raw [Listener] this track used to be reported a tap (F-200).
  int? _reported;

  int get _lastFrame => widget.frameCount <= 1 ? 0 : widget.frameCount - 1;

  void _begin(double x, double width) {
    _reported = null;
    _apply(x, width);
  }

  void _apply(double x, double width) {
    if (_lastFrame == 0) {
      return;
    }
    final frame = _frameAt(x, width, _lastFrame);
    if (frame == _reported) {
      return;
    }
    _reported = frame;
    widget.onSeek(frame);
  }

  @override
  Widget build(BuildContext context) {
    final kept = widget.kept;
    return _TrackGrip(
      keyValue: widget.keyValue,
      height: widget.height,
      onPress: _begin,
      onMove: _apply,
      painter: _SeekPainter(
        position: _fractionOf(widget.currentFrame, _lastFrame),
        keptStart: kept == null ? null : _fractionOf(kept.first, _lastFrame),
        keptEnd: kept == null ? null : _fractionOf(kept.last, _lastFrame),
        wash: TransportBar.rangeWash,
        enabled: _lastFrame > 0,
      ),
    );
  }
}

class _SeekPainter extends CustomPainter with RepaintOnProps {
  const _SeekPainter({
    required this.position,
    required this.keptStart,
    required this.keptEnd,
    required this.wash,
    required this.enabled,
  });

  final double position;
  final double? keptStart;
  final double? keptEnd;

  /// ⚠️A prop, not read in [paint]: the accent is live, and a painter that
  /// read it there would keep the old one until something else moved.
  final Color wash;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    _paintTrackGround(canvas, size, enabled: enabled);
    final start = keptStart;
    final end = keptEnd;
    if (start != null && end != null) {
      canvas.drawRect(
        Rect.fromLTRB(start * size.width, 0, end * size.width, size.height),
        Paint()..color = wash,
      );
    }
    _paintMarker(
      canvas,
      size,
      position * size.width,
      dimmedIfDisabled(AppColors.text, enabled: enabled),
    );
  }

  @override
  Object get props => (position, keptStart, keptEnd, wash, enabled);
}

/// Which handle a press on the range track took.
enum _Handle {
  inHandle,
  outHandle,

  /// Both stand on one frame, and the press is on them: the way the hand
  /// first goes says which it meant.
  either,
}

const double _handleGrabPixels = 10;

/// The range track: the span between its two handles is washed, and a
/// handle is taken by pressing near it.
///
/// 🗣️유저 2026-10-06: 「지금 ui가 인아웃 조절버튼이 너무 두껍고 이상하니
/// 재생바의 프레임위치 세로선이랑 똑같이 얇게하는데 색만 강조색으로」 — each
/// handle is the playhead's hairline in the accent.
///
/// A press within [_handleGrabPixels] of a handle takes that handle for
/// the whole drag, the nearer of the two; a press anywhere else on the
/// track moves neither (a tablet hand is not precise, and a mis-dragged IN
/// edits the import). Either way the press is the track's.
class TransportRangeTrack extends StatefulWidget {
  const TransportRangeTrack({
    super.key,
    required this.frameCount,
    required this.inFrame,
    required this.outFrame,
    required this.onChanged,
    this.keyValue = 'transport-range',
    this.height = 12,
  });

  final int frameCount;
  final int inFrame;
  final int outFrame;

  /// See [TransportRange.onChanged] — null stands the track off.
  final void Function(int inFrame, int outFrame)? onChanged;

  final String keyValue;
  final double height;

  @override
  State<TransportRangeTrack> createState() => _TransportRangeTrackState();
}

class _TransportRangeTrackState extends State<TransportRangeTrack> {
  /// The handle the press under way took, or null when it took none.
  _Handle? _handle;

  /// The frame this press last reported — see [_TransportTrackState].
  int? _reported;

  int get _lastFrame => widget.frameCount <= 1 ? 0 : widget.frameCount - 1;

  void _begin(double x, double width) {
    _reported = null;
    _handle = _handleNear(x, width);
    _apply(x, width);
  }

  _Handle? _handleNear(double x, double width) {
    final toIn = (x - _fractionOf(widget.inFrame, _lastFrame) * width).abs();
    final toOut = (x - _fractionOf(widget.outFrame, _lastFrame) * width).abs();
    if (math.min(toIn, toOut) > _handleGrabPixels) {
      return null;
    }
    if (widget.inFrame == widget.outFrame) {
      return _Handle.either;
    }
    return toIn <= toOut ? _Handle.inHandle : _Handle.outHandle;
  }

  void _apply(double x, double width) {
    final onChanged = widget.onChanged;
    if (onChanged == null || _handle == null) {
      return;
    }
    final frame = _frameAt(x, width, _lastFrame);
    if (_handle == _Handle.either) {
      if (frame == widget.inFrame) {
        return;
      }
      _handle = frame < widget.inFrame ? _Handle.inHandle : _Handle.outHandle;
    }
    if (frame == _reported) {
      return;
    }
    _reported = frame;
    if (_handle == _Handle.inHandle) {
      onChanged(math.min(frame, widget.outFrame), widget.outFrame);
    } else {
      onChanged(widget.inFrame, math.max(frame, widget.inFrame));
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.onChanged != null;
    return _TrackGrip(
      keyValue: widget.keyValue,
      height: widget.height,
      onPress: _begin,
      onMove: _apply,
      painter: _RangePainter(
        start: _fractionOf(widget.inFrame, _lastFrame),
        end: _lastFrame == 0 ? 1 : _fractionOf(widget.outFrame, _lastFrame),
        wash: TransportBar.rangeWash,
        handle: AppColors.accent,
        enabled: live,
      ),
    );
  }
}

class _RangePainter extends CustomPainter with RepaintOnProps {
  const _RangePainter({
    required this.start,
    required this.end,
    required this.wash,
    required this.handle,
    required this.enabled,
  });

  final double start;
  final double end;

  /// ⚠️Props, as the seek track's wash is ([_SeekPainter.wash]).
  final Color wash;
  final Color handle;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    _paintTrackGround(canvas, size, enabled: enabled);
    final startX = start * size.width;
    // IN's line is drawn from its place rightwards and OUT's leftwards, so
    // each stands inside the track where the span reaches an end of it.
    final endX = math.max(startX, end * size.width - 1);
    canvas.drawRect(
      Rect.fromLTRB(startX, 0, endX + 1, size.height),
      Paint()..color = dimmedIfDisabled(wash, enabled: enabled),
    );
    final ink = dimmedIfDisabled(handle, enabled: enabled);
    _paintMarker(canvas, size, startX, ink);
    _paintMarker(canvas, size, endX, ink);
  }

  @override
  Object get props => (start, end, wash, handle, enabled);
}
