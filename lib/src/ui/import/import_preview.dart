import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/kept_span.dart';
import '../../models/media_asset.dart';
import '../../models/project_frame_rate.dart';
import '../../native/qa_native_engine.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../../services/media/media_byte_source.dart';
import '../../services/media/viewer_document.dart';
import '../../services/project_lookup.dart' show mediaKindCanCarrySound;
import '../audio/waveform_painter.dart';
import '../editor_session_manager.dart';
import '../effective_device_pixel_ratio.dart';
import '../media/audio_viewer_document.dart';
import '../media/media_run.dart';
import '../media/open_viewer_document.dart';
import '../media/page_rasters.dart';
import '../media/viewer_raster_budget.dart';
import '../media/viewer_render_tier.dart';
import '../media/viewer_sound.dart';
import '../theme/app_theme.dart';
import '../widgets/checkered_picture.dart';
import '../widgets/transport_bar.dart';

/// The import window's right-hand zone: the selected file, and the bar that
/// walks through it — and PLAYS it, sound and all.
///
/// The picture is FITTED into a 16:9 box and nothing else is drawn — no
/// canvas outline, no placement rectangle. What the window is showing here
/// is the source, not the composition; the composition is what Fit answers
/// in the row.
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
/// A sound is its waveform, run over the frames it lasts, with the span
/// IN/OUT keep washed on it (the mockup's window for a sound — 유저
/// 2026-09-11: 「거기서 가져올 구간을 줄이면 블록도 그만큼 줄어든다」).
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

  /// The narrowest this zone lays out: the transport's own minimum. The
  /// window gives the file table the rest.
  static const double minimumWidth = TransportBar.minimumWidth;

  @override
  State<ImportPreview> createState() => _ImportPreviewState();
}

class _ImportPreviewState extends State<ImportPreview>
    implements MediaRunSurface {
  /// The file shown, as the viewer would open it — or null while nothing
  /// is, or nothing here reads it.
  ViewerDocument? _document;
  String? _loadedPath;
  bool _loadedAsSound = false;

  /// The page under the playhead: a movie's project frame, a PDF's page, a
  /// GIF's frame. A sound's playhead is its run's seconds instead
  /// ([MediaRun.soundSeconds]) — a waveform is one page.
  int _page = 0;

  /// Where this preview's pages are counted in the memory census
  /// ([RenderCaches.viewerRasterBytesByViewer]).
  static const String _censusKey = 'import-preview';

  late final PageRasters _rasters = PageRasters(
    budget: ViewerRasterBudget(
      physicalMemoryBytes: QaNativeEngine.instance?.physicalMemoryBytes,
    ),
    document: () => _document,
    distance: (page) => _run.distanceTo(page),
    rebuild: setState,
    mounted: () => mounted,
    report: (bytes) =>
        widget.session.renderCaches.viewerRasterBytesByViewer[_censusKey] =
            bytes,
  );

  late final MediaRun _run = MediaRun(
    surface: this,
    rasters: _rasters,
    sound: widget.sound ?? ViewerSound.ofSession(widget.session),
  );

  @override
  void initState() {
    super.initState();
    widget.session.memoryPressureTicks.addListener(_onMemoryPressure);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(ImportPreview old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || old.opensAsSound != widget.opensAsSound) {
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
    final document = _document;
    _document = null;
    if (document != null) {
      unawaited(document.dispose());
    }
  }

  Future<void> _load() async {
    final path = widget.path;
    final asSound = widget.opensAsSound;
    if (path == _loadedPath && asSound == _loadedAsSound) {
      return;
    }
    _loadedPath = path;
    _loadedAsSound = asSound;
    _close();
    if (path == null) {
      setState(() {});
      return;
    }
    // By the key the pool and the conform store know it by — the window
    // conforms each movie's sound under it the moment the file is listed,
    // so the press that plays it finds the sound already there.
    final key = normalizedMediaPath(path);
    final kind = asSound ? MediaAssetKind.audio : mediaAssetKindForPath(key);
    ViewerDocument? document;
    try {
      document = kind == null
          ? null
          : await openViewerDocument(
              kind,
              key,
              hold: widget.holdBytes,
              soundPeaks: widget.soundPeaks,
              projectClock: (rate: widget.frameRate, speed: widget.audioSpeed),
            );
    } on Object {
      // A file being written as we look at it, a movie this build cannot
      // read: the zone shows nothing rather than an error nobody asked
      // for. What cannot be imported is already named in the footer.
      document = null;
    }
    if (!mounted || _loadedPath != path || _loadedAsSound != asSound) {
      unawaited(document?.dispose());
      return;
    }
    setState(() => _document = document);
  }

  // --- The run's surface ([MediaRunSurface]) -------------------------------

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _stage(frameCount)),
        const Divider(height: 1),
        _transport(frameCount),
      ],
    );
  }

  /// The picture in its 16:9 well, over the app's ONE transparency checker —
  /// the export preview's own shape, shared (유저 2026-09-11: 「임포트의
  /// 미리보기에서 배경이 투명한파일은 출력창의 미리보기에서 쓰는 …
  /// 격자무늬 그대로 공용화해서 재사용하도록」). It used to draw the file
  /// straight onto the dark well, where open alpha and a dark picture look
  /// the same. A sound has no open alpha to show: its waveform stands on
  /// the well itself.
  Widget _stage(int frameCount) => ColoredBox(
    color: AppColors.backdrop,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Center(
        child: AspectRatio(aspectRatio: 16 / 9, child: _shown(frameCount)),
      ),
    ),
  );

  Widget _shown(int frameCount) {
    final sound = _sound;
    if (sound != null) {
      return _waveform(sound, frameCount);
    }
    final document = _document;
    if (document == null || document.pageCount == 0) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, box) {
        final picture = _pictureOf(context, document, box.biggest);
        return picture == null
            ? const SizedBox.shrink()
            : CheckeredPicture(
                image: picture,
                checkerKey: const ValueKey<String>('import-preview-checker'),
              );
      },
    );
  }

  /// Asks for the page under the playhead at the pixels it will be drawn
  /// at — the viewer's ladder ([viewerRenderScaleFor]) over the box it is
  /// fitted into — and answers whatever the cache holds for it (a blurrier
  /// render of the SAME page is not a lie about which frame this is).
  ui.Image? _pictureOf(BuildContext context, ViewerDocument document, Size box) {
    final page = _page.clamp(0, document.pageCount - 1);
    final size = document.pageSize(page);
    if (size.width > 0 && size.height > 0) {
      final fitted = math.min(box.width / size.width, box.height / size.height);
      final scale = viewerRenderScaleFor(
        fitted * EffectiveDevicePixelRatio.of(context),
        size,
      );
      _rasters
        ..scale = scale
        ..shown = {page}
        ..ensureRendered(page, scale);
      _run.fillBuffer();
    }
    return _rasters.imageOf(page);
  }

  /// A sound's picture — the viewer's painter in the viewer's ink
  /// ([AudioViewerDocument.ink]) — over the frames the transport counts,
  /// with the span IN/OUT keep washed as the transport's range is.
  Widget _waveform(AudioPeaks sound, int frameCount) => LayoutBuilder(
    builder: (context, constraints) {
      final perFrame = constraints.maxWidth / frameCount;
      final kept = _kept(frameCount);
      return Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            key: const ValueKey<String>('import-preview-waveform'),
            painter: WaveformPainter(
              peaks: sound,
              frameRate: widget.frameRate,
              pixelsPerFrame: perFrame,
              color: AudioViewerDocument.ink,
            ),
          ),
          // Always there, clear while IN/OUT do not bite — nothing pops in.
          Positioned(
            left: kept.first * perFrame,
            width: kept.count * perFrame,
            top: 0,
            bottom: 0,
            child: DecoratedBox(
              key: const ValueKey<String>('import-preview-kept-span'),
              decoration: _rangeShown(frameCount)
                  ? BoxDecoration(
                      color: TransportBar.rangeWash,
                      border: Border.symmetric(
                        vertical: BorderSide(color: AppColors.accent, width: 2),
                      ),
                    )
                  : const BoxDecoration(),
            ),
          ),
        ],
      );
    },
  );

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
