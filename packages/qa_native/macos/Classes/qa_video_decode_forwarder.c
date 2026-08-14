// Forwarder — CocoaPods podspecs cannot reference files outside their own
// directory, so Classes/ includes the real source (see the note in
// qa_native_forwarder.c).
#include "../../src/qa_video_decode.c"
