import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/place_lines.dart';

const _clap = 'C:/media/clap.wav';

Cut _cut(String id) => Cut(
  id: CutId(id),
  name: id,
  duration: 12,
  canvasSize: const CanvasSize(width: 640, height: 360),
  layers: [
    Layer(
      id: LayerId('$id-a'),
      name: 'A',
      frames: [Frame(id: FrameId('$id-a1'), duration: 1, strokes: const [])],
    ),
  ],
);

/// Two cuts of twelve frames, and a sound on the track's S1 two frames into
/// the second: frame 14 of the track, which no cut's own count says.
Project _project() => Project(
  id: const ProjectId('a-frame-in-a-list'),
  name: 'A frame in a list',
  createdAt: DateTime.utc(2026, 10, 7),
  mediaAssets: [MediaAsset(path: _clap, name: 'clap.wav')],
  tracks: [
    Track(
      id: const TrackId('t1'),
      name: 'Video',
      cuts: [_cut('c1'), _cut('c2')],
      seLayers: [
        Layer(
          id: const LayerId('s1'),
          name: 'S1',
          kind: LayerKind.se,
          frames: [
            Frame(id: const FrameId('hit'), duration: 1, strokes: const []),
          ],
          timeline: {
            14: const TimelineExposure.drawing(FrameId('hit'), length: 2),
          },
          audioClips: [
            AudioClip(filePath: _clap, frameId: const FrameId('hit')),
          ],
        ),
      ],
    ),
  ],
);

/// 🗣️F-284 (유저 2026-10-04): 「링크된 오디오 링크버튼눌러서 쓰는곳
/// 확인할때, 인덱스도 표시. 예를들어 se는 지금 S1 등 트랙이름까지만
/// 표시되는데, S1의 15. 이런식으로 15번 인덱스나. 이런 표기는 초+코마
/// 표기로 바꾼거에 대응하도록 법 통일」.
///
/// The session has ONE way of writing a frame's place
/// (`framePlaceLabel`), and it is the ruler's: the number over the block,
/// and under the seconds display the second before it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('🚨where a file is used says the frame, as the ruler over the row '
      'writes it — and follows the seconds display and the project\'s '
      'rate', () {
    final session = EditorSessionManager(initialProject: _project());
    addTearDown(session.dispose);

    List<String> uses() => [
      for (final use in session.mediaPool.mediaAssetUses(_clap))
        mediaAssetUseLine(use, framePlace: session.framePlaceLabel),
    ];

    expect(
      uses(),
      ['Video · S1 · 15'],
      reason: 'the track\'s frame: its row is the track\'s, and so is the '
          'ruler over it',
    );

    session.appSettings.showSecondsDisplay.value = true;
    expect(uses(), ['Video · S1 · 0+15']);

    session.projectSettings.setProjectFps(12);
    expect(uses(), ['Video · S1 · 1+3'], reason: 'a second is twelve now');

    session.appSettings.showSecondsDisplay.value = false;
    expect(uses(), ['Video · S1 · 15']);
  });
}
