import '../../services/playback/frame_demand.dart';
import '../quiet_turns.dart' show QuietTurns, notDue;

/// What a frame's picture is made of, where the screen that shows it looks
/// for it — asked by the one maker of playback's pictures, and through it by
/// a run that waits for one and the ruler's bar that counts them, so none of
/// them can mean a different picture from the one the screen draws
/// (playback-plays-the-screen-material).
abstract interface class PlaybackPictures {
  /// Whether [picture] is there to show.
  bool has(DemandedPicture picture);

  /// The parts of [picture] not there yet that making it would make, each
  /// by an identity two frames showing it share — what a walk asking ahead
  /// counts so a part is asked for once.
  Set<Object> partsToMake(DemandedPicture picture);

  /// Where [picture] stands — there, never to come, or still to come — and
  /// whether a cel it shows could not be read at the content it has now:
  /// what a run asks before it goes on and what the ruler's bar paints, off
  /// ONE reading of the frame.
  ///
  /// 🪶WHY ONE (card frame-panels-build-in-one-frame, 2026-10-28): a
  /// frame's key is its stack walked and signed, and [has] and then a
  /// separate "did it fail" walked it twice for every frame still to come —
  /// the storyboard's bar asks it of every span of the film whenever the
  /// panel is shown again — and the bar walked the stack a third time for
  /// its red.
  PictureStanding standingOf(DemandedPicture picture);

  /// Remembers that making [picture] threw at the content it has now.
  void noteFailure(DemandedPicture picture);

  /// The bytes making [picture] would add — what its parts will be made as,
  /// where what they are made of is in hand ([readIn]).
  int bytesToMake(DemandedPicture picture);

  /// Reads in what making [picture] reads first, so [bytesToMake] weighs it
  /// by what it will be made as. Never throws: what will not read is said by
  /// [make].
  Future<void> readIn(DemandedPicture picture);

  /// The bytes [picture] holds that [seen] has not counted, which it adds to
  /// [seen]: a walk weighs the window it has passed over by this, each
  /// picture's parts counted once however many frames show them.
  int weighNew(DemandedPicture picture, Set<Object> seen);

  /// Makes [picture]: true when it landed, false when [shouldAbort] stood it
  /// down. Throws where its content cannot be read.
  ///
  /// What it puts on the GPU waits for the quiet between a run's held frames
  /// ([QuietTurns]) — except while [due]: then the run's next held frame
  /// shows what is being made, and the quiet that frame leaves comes too
  /// late for it.
  Future<bool> make(
    DemandedPicture picture, {
    required bool Function() shouldAbort,
    bool Function() due = notDue,
  });
}

/// Where a frame's picture is ([PlaybackPictures.standingOf]).
enum PictureState {
  /// There to show.
  there,

  /// Never to come: making it threw at the content it has now — it is not
  /// waited for, nor made again until that content changes
  /// ([PlaybackPictures.noteFailure]).
  gaveUp,

  /// Still to be made.
  toCome,
}

/// Where a frame's picture is, and whether a cel it shows could not be
/// read at the content it has now ([PlaybackPictures.standingOf]).
typedef PictureStanding = ({PictureState state, bool cannotRead});
