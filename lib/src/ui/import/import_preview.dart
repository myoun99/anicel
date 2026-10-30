import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../models/canvas_viewport.dart';
import '../../models/kept_span.dart';
import '../../models/media_asset.dart';
import '../../models/project_frame_rate.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../../services/media/media_byte_source.dart';
import '../../services/media/viewer_document.dart';
import '../../services/project_lookup.dart' show mediaKindCanCarrySound;
import '../brush/brush_canvas_panel.dart' show CanvasTransportBand;
import '../canvas/viewport_pages_painter.dart' show ViewportPageGround;
import '../editor_session_manager.dart';
import '../effective_device_pixel_ratio.dart';
import '../media/audio_viewer_document.dart';
import '../media/document_preview_panel.dart';
import '../media/media_run.dart';
import '../media/open_viewer_document.dart';
import '../media/page_rasters.dart';
import '../media/picture_run_document.dart';
import '../media/viewer_page_loading.dart';
import '../media/viewer_pages_and_run.dart';
import '../media/viewer_sound.dart';
import '../media/waveform_marks_painter.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state_text.dart';
import '../widgets/transport_bar.dart';

/// The import window's right-hand zone: the selected file, and the bar that
/// walks through it — and PLAYS it, sound and all.
///
/// The file stands in the export window's preview panel
/// ([DocumentPreviewPanel] — 유저 2026-10-09: 「임포트창 미리보기도 출력창
/// 미리보기 개편한것처럼 공용화된거 쓰는거 잊지말고」), and nothing else is
/// drawn — no canvas outline, no placement rectangle. What the window is
/// showing here is the source, not the composition; the composition is
/// what Fit answers in the row. ↩️It was fitted into a 16:9 well, with no
/// zoom.
///
/// 🚨★★★**THE MEDIA VIEWER'S DOCUMENT, PAGES AND RUN — the same code, not a
/// second player.** 유저 2026-09-27: 「임포트창에서 재생해도 소리안나고
/// 재생되는지도모르겟네. 뷰어패널이랑 통일할거하면서 소리나게」. The file
/// opens through the viewer's door ([openViewerDocument]), its pages are
/// drawn from the viewer's cache ([PageRasters]) and the play button runs
/// the viewer's run ([MediaRun]) — whose sound, whose wait for a frame that
/// has not landed, and whose device clock were all written once, there.
/// 🪦The button used to be `onPlayPause: () {}` under 「Playback belongs to
/// the day a video arrives」 — the video arrived, and the button stayed a
/// control that did nothing.
///
/// What is the window's own is how it COUNTS: a movie in the frames a
/// placement counts ([ProjectClockDocument] — the IN/OUT here is what
/// lands), a sound in the project's frames over its length, a PDF and a GIF
/// in their pages. The bar never learns what is behind them.
///
/// A sound is the viewer's waveform page under the viewer's playhead, with
/// the span IN/OUT keep washed on it (the mockup's window for a sound —
/// 유저 2026-09-11: 「거기서 가져올 구간을 줄이면 블록도 그만큼
/// 줄어든다」).
class ImportPreview extends StatefulWidget {
  const ImportPreview({
    super.key,
    required this.session,
    required this.path,
    required this.inFrame,
    required this.outFrame,
    required this.onRangeChanged,
    required this.rangeEditable,
    required this.soundPeaks,
    required this.holdBytes,
    required this.frameRate,
    this.audioSpeed = (numerator: 1, denominator: 1),
    this.sound,
    this.opensAsSound = false,
    this.run,
  });

  /// The session the window imports into: the census its pages are counted
  /// in, the memory warnings they hear, and the output its sound plays
  /// through ([ViewerSound.ofSession]).
  final EditorSessionManager session;

  /// The file being looked at, or null when nothing is selected.
  final String? path;

  final int inFrame;
  final int? outFrame;
  final void Function(int inFrame, int? outFrame) onRangeChanged;

  /// Whether IN/OUT can act on anything. A range that changes nothing is a
  /// control that lies, so the ends are shown only where they bite: a
  /// multi-frame source being PLACED.
  final bool rangeEditable;

  /// A sound's peaks once its conform has them
  /// (`AudioConformStore.ensurePeaksFor`); null when it never will.
  final Future<AudioPeaks?> Function(String path) soundPeaks;

  /// Where a picture's, a PDF's or a movie's bytes are
  /// (`ProjectFile.holdMediaBytes`) — the project's own copy first, so a
  /// file the pool carries shows what the project holds, whatever became of
  /// its original.
  final HoldMediaBytes holdBytes;

  /// The project's rate: a sound runs over the frames IN/OUT and the block
  /// it becomes are counted in.
  final ProjectFrameRate frameRate;

  /// The project's accumulated audio pull. A movie's frames are counted on
  /// the SOUND's clock ([ProjectClockDocument]) — the frames its IN/OUT and
  /// the block it becomes are counted in, the same ones a sound's are.
  final ({int numerator, int denominator}) audioSpeed;

  /// This preview's sound, or null for the session's — the seam a test
  /// hands a device through, as the viewer's is
  /// ([MediaViewerTabHost.sound]).
  final ViewerSound? sound;

  /// Whether the file is shown as its SOUND — a movie that brings its sound
  /// alone ([MovieParts.sound]) shows the waveform that lands, counted in
  /// the frames its trim is counted in, not the picture that does not.
  final bool opensAsSound;

  /// The pictures of the numbered run [path] is part of, in order — null
  /// for a file in none. A run is paged through as one document
  /// ([PictureRunDocument]), and its IN/OUT pick the pictures that come in
  /// (F-282, 유저 2026-10-09: 「연번은 들어갈 범위만(A2–A3) — 미리보기의
  /// IN/OUT, 동영상과 같은 법」).
  final List<String>? run;

  /// The narrowest this zone lays out: the transport's own minimum. The
  /// window gives the file table the rest.
  static double minimumWidthIn(BuildContext context) =>
      TransportBar.minimumWidthIn(context);

  @override
  State<ImportPreview> createState() => _ImportPreviewState();
}

class _ImportPreviewState extends State<ImportPreview>
    with TickerProviderStateMixin
    implements MediaRunSurface {
  /// The file shown, as the viewer would open it — or null while nothing
  /// is, or nothing here reads it.
  ViewerDocument? _document;
  String? _loadedPath;
  bool _loadedAsSound = false;
  List<String>? _loadedRun;

  /// Whether the file is still being opened: the zone says it is loading
  /// until it lands, or turns out to be nothing this window reads.
  bool _opening = false;

  /// What stands in the picture's place when the door gave none — the media
  /// viewer's own sentence for the same open ([viewerCouldNotOpen],
  /// [viewerNothingOpens]) — or null while nothing was refused.
  ///
  /// 🐞The zone stood empty instead, under 「shows nothing rather than an
  /// error nobody asked for — what cannot be imported is already named in
  /// the footer」 (2026-08-14, when it showed pictures alone and a movie or a
  /// PDF could not be shown at all). The footer names nothing until Import
  /// is pressed, so a movie the device could not open stood as a black well
  /// counting 1 / 1, and Import then said only that it could not be imported
  /// (유저 2026-10-30, Galaxy Tab, build 1084).
  String? _refusal;

  /// The page under the playhead: a movie's project frame, a PDF's page, a
  /// GIF's frame. A sound's playhead is its run's seconds instead
  /// ([MediaRun.soundSeconds]) — a waveform is one page.
  int _page = 0;

  /// Where this preview's pages are counted in the memory census
  /// ([RenderCaches.viewerRasterBytesByViewer]).
  static const String _censusKey = 'import-preview';

  late final ViewerPagesAndRun _pagesAndRun = ViewerPagesAndRun(
    surface: this,
    sound: widget.sound ?? ViewerSound.ofSession(widget.session),
    report: (bytes) =>
        widget.session.renderCaches.viewerRasterBytesByViewer[_censusKey] =
            bytes,
  );
  PageRasters get _rasters => _pagesAndRun.rasters;
  MediaRun get _run => _pagesAndRun.run;

  @override
  void initState() {
    super.initState();
    widget.session.memoryPressureTicks.addListener(_onMemoryPressure);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(ImportPreview old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path ||
        old.opensAsSound != widget.opensAsSound ||
        !listEquals(old.run, widget.run)) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    widget.session.memoryPressureTicks.removeListener(_onMemoryPressure);
    _close();
    _run.dispose();
    widget.session.renderCaches.viewerRasterBytesByViewer.remove(_censusKey);
    super.dispose();
  }

  void _onMemoryPressure() => _rasters.heardMemoryPressure(keeping: _page);

  /// Lets go of the file shown — its run, its pages and the document.
  void _close() {
    _run.letGo();
    _rasters.clear();
    _page = 0;
    _refusal = null;
    final document = _document;
    _document = null;
    if (document != null) {
      unawaited(document.dispose());
    }
  }

  Future<void> _load() async {
    final path = widget.path;
    final asSound = widget.opensAsSound;
    final run = widget.run;
    bool stillAsked() =>
        _loadedPath == path &&
        _loadedAsSound == asSound &&
        listEquals(_loadedRun, run);
    if (stillAsked()) {
      return;
    }
    _loadedPath = path;
    _loadedAsSound = asSound;
    _loadedRun = run;
    _close();
    _opening = path != null;
    if (path == null) {
      setState(() {});
      return;
    }
    // By the key the pool and the conform store know it by — the window
    // conforms each movie's sound under it the moment the file is listed,
    // so the press that plays it finds the sound already there.
    final key = normalizedMediaPath(path);
    final kind = asSound ? MediaAssetKind.audio : mediaAssetKindForPath(key);
    // A run is pictures; a file of no medium's kind asks nothing, so it is
    // refused nothing.
    final asked = run != null ? MediaAssetKind.image : kind;
    ViewerDocument? document;
    String? refusal;
    try {
      document = run != null
          ? await PictureRunDocument.open(run, hold: widget.holdBytes)
          : kind == null
          ? null
          : await openViewerDocument(
              kind,
              key,
              hold: widget.holdBytes,
              soundPeaks: widget.soundPeaks,
              projectClock: (rate: widget.frameRate, speed: widget.audioSpeed),
            );
      if (document == null && asked != null) {
        refusal = viewerNothingOpens(asked);
      }
    } on Object catch (error) {
      document = null;
      refusal = viewerCouldNotOpen(error);
    }
    if (!mounted || !stillAsked()) {
      unawaited(document?.dispose());
      return;
    }
    setState(() {
      _document = document;
      _refusal = refusal;
      _opening = false;
    });
  }

  // --- The run's surface ([MediaRunSurface]) -------------------------------

  @override
  TickerProvider get vsync => this;

  @override
  ProjectFrameRate get frameRate => widget.frameRate;

  @override
  ViewerDocument? get document => _document;

  @override
  int get page => _page;

  @override
  void turnToPage(int page) {
    final count = _document?.pageCount ?? 0;
    setState(() => _page = count <= 0 ? 0 : page.clamp(0, count - 1));
  }

  /// ⛔It asks [mediaKindCanCarrySound], as the viewer does — a movie
  /// carries a soundtrack, and deciding that here would be a second place
  /// the app answers 「이게 소리를 가질 수 있나」.
  @override
  String? get soundPath {
    final path = _loadedPath;
    final key = path == null ? null : normalizedMediaPath(path);
    final kind = key == null ? null : mediaAssetKindForPath(key);
    return _document != null && kind != null && mediaKindCanCarrySound(kind)
        ? key
        : null;
  }

  @override
  ViewerLoudness get loudness => _loudness;

  /// How loud this preview plays — the window's, for as long as it is open.
  ViewerLoudness _loudness = const ViewerLoudness();

  /// A sound's picture, or null when the file is not one.
  AudioPeaks? get _sound => switch (_document) {
    final AudioViewerDocument waveform => waveform.peaks,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    // What the transport counts is the run's ([MediaRun.frameCount]): a
    // sound in the project's frames over its length, anything else its
    // pages.
    final frameCount = _run.frameCount(widget.frameRate);
    final document = _document;
    final shown = document == null || document.pageCount == 0
        ? null
        : document;
    final run = _loadedRun;
    // A run's plate names the picture stood on (the mockup: 「A2.png ·
    // 2 / 3」); anything else's, its file.
    final path = run != null && shown != null
        ? run[_page.clamp(0, run.length - 1)]
        : _loadedPath;
    final sound = _sound != null;
    return DocumentPreviewPanel(
      keyPrefix: 'import-preview',
      pagesAndRun: _pagesAndRun,
      document: shown,
      page: shown == null ? 0 : _page.clamp(0, shown.pageCount - 1),
      nothing: _opening ? _loading : _refused(),
      // The app's ONE transparency checker under a picture — the export
      // preview's own, shared (유저 2026-09-11: 「임포트의 미리보기에서
      // 배경이 투명한파일은 출력창의 미리보기에서 쓰는 … 격자무늬 그대로
      // 공용화해서 재사용하도록」): on the bare backdrop, open alpha and a
      // dark picture look the same. A sound has no open alpha to show; its
      // band stands on the backdrop itself.
      ground: sound ? ViewportPageGround.none : ViewportPageGround.checker,
      // The window trims, so its transport is always there.
      transport: CanvasTransportBand(
        height: TransportBar.heightIn(context, range: true),
        child: _transport(frameCount),
      ),
      documentName: path == null
          ? null
          : widget.session.repository.requireProject().shownNameOfMedia(path),
      marks: sound
          ? (viewport, page) => _soundMarks(viewport, page, frameCount)
          : null,
    );
  }

  /// The file still opening (F-315). ↩️The well stood empty.
  static const Widget _loading = ViewerPageLoading(
    key: ValueKey<String>('import-preview-loading'),
  );

  /// Why the door gave no picture ([_refusal]), where the picture would be
  /// — or nothing.
  Widget _refused() {
    final refusal = _refusal;
    return refusal == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.all(24),
            child: EmptyStateText(
              refusal,
              key: const ValueKey<String>('import-preview-refused'),
              place: EmptyStatePlace.stage,
            ),
          );
  }

  /// A sound's marks over its band — the viewer's ([WaveformMarksPainter]):
  /// where the playhead stands, and the span IN/OUT keep, washed as the
  /// transport's range is. The layer is always there and clear while IN/OUT
  /// do not bite, so nothing pops in when they start to.
  Widget _soundMarks(CanvasViewport viewport, ui.Size page, int frameCount) {
    final kept = _kept(frameCount);
    final rate = widget.frameRate;
    return CustomPaint(
      key: const ValueKey<String>('import-preview-marks'),
      painter: WaveformMarksPainter(
        atSeconds: _run.soundSeconds,
        ofSeconds: _run.soundLengthSeconds ?? 0,
        docSize: page,
        viewport: viewport,
        effectiveRatio: EffectiveDevicePixelRatio.of(context),
        color: AppColors.accent,
        kept: _rangeShown(frameCount)
            ? (
                from: rate.frameStartSeconds(kept.first),
                to: rate.frameStartSeconds(kept.last + 1),
              )
            : null,
      ),
      child: const SizedBox.expand(),
    );
  }

  /// What IN/OUT keep of [frameCount] frames — the transport's ends and the
  /// waveform's wash read this one answer.
  KeptSpan _kept(int frameCount) => KeptSpan(
    length: frameCount,
    inFrame: widget.inFrame,
    outFrame: widget.outFrame,
  );

  /// IN/OUT bite only on a multi-frame source being placed.
  bool _rangeShown(int frameCount) => widget.rangeEditable && frameCount > 1;

  Widget _transport(int frameCount) {
    final kept = _kept(frameCount);
    return TransportBar(
      frameCount: frameCount,
      currentFrame: _run.frameAt(widget.frameRate).clamp(0, frameCount - 1),
      playing: _run.playing,
      onSeek: (frame) => _run.seekToFrame(frame, widget.frameRate),
      // A still or a PDF has nothing that advances by itself and no sound:
      // the button stays where it is, and says so by being off.
      onPlayPause: _run.canPlay ? _run.toggle : null,
      sound: _run.soundCell(
        onChanged: (next) => setState(() => _loudness = next),
      ),
      // The window trims, so the row is always here — and off where IN/OUT
      // would act on nothing.
      range: TransportRange(
        inFrame: kept.first,
        outFrame: kept.last,
        onChanged: _rangeShown(frameCount)
            ? (start, end) => widget.onRangeChanged(
                start,
                end >= frameCount - 1 ? null : end,
              )
            : null,
      ),
    );
  }
}
