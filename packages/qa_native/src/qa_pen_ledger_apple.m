// THE PEN LEDGER (H43) — what the platform said about each pen sample,
// written down BEFORE Flutter hears of it, and read by the brush
// synchronously, by the sample's own timestamp.
//
// Why a ledger and not a channel: a channel message and a pointer event
// travel two queues with no order between them, and the brush has to know
// about THIS sample while it handles THIS sample. A write that happens
// before the event reaches Flutter, read through FFI while the event is
// being handled, cannot arrive late.
//
// iOS — UIKit's word on Apple Pencil force and altitude. Either can be an
// ESTIMATE when a sample is taken (`estimatedPropertiesExpectingUpdates`),
// and the measured value comes later through
// `touchesEstimatedPropertiesUpdated`, which Flutter's engine does not
// implement. The Runner's view controller hands both to
// +[QaPenLedger noteTouches:] and +[QaPenLedger updateTouches:] ahead of its
// super calls. (Location can be estimated too; the brush does not wait on
// position, so it is not kept.)
//
// macOS — the tablet pressure Flutter's embedder drops. A local event
// monitor (qa_pen_ledger_start) sees every left-mouse event before the
// window does and writes its pressure, or that it is not a tablet event.
//
// Compiled for Apple only, through the ios/ and macos/ Classes forwarders.

#import <TargetConditionals.h>
#import <Foundation/Foundation.h>
#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#elif TARGET_OS_OSX
#import <AppKit/AppKit.h>
#endif

#include <os/lock.h>
#include <stdint.h>

#define QA_EXPORT __attribute__((visibility("default")))

enum {
  QA_PEN_MEASURED = 0,
  QA_PEN_ESTIMATED = 1,
  QA_PEN_NO_PRESSURE = 2,
  QA_PEN_UNREPORTED = 3,  // The platform never reports this property.
};

typedef struct {
  int64_t micros;
  int64_t update_index;  // UIKit's estimationUpdateIndex; -1 when none.
  double value;          // Force (iOS) or pressure (macOS).
  double altitude;       // Radians from the surface (iOS only).
  int32_t state;
  int32_t altitude_state;
  int32_t used;
} QaPenSample;

// Far more samples than one stroke's wait can span: the brush asks about a
// sample within milliseconds of recording it.
#define QA_PEN_RING 512

static QaPenSample qa_pen_ring[QA_PEN_RING];
static int qa_pen_next = 0;
static os_unfair_lock qa_pen_lock = OS_UNFAIR_LOCK_INIT;

// The key Flutter itself stamps the pointer event with: the platform
// timestamp times 1000000, truncated into an integer (iOS:
// FlutterViewController's dispatchTouches; macOS: the embedder's mouse
// events). The same arithmetic here makes the two keys equal.
static int64_t qa_pen_micros(NSTimeInterval timestamp) {
  return (int64_t)(timestamp * 1000000);
}

static void qa_pen_record(int64_t micros, double value, int32_t state,
                          double altitude, int32_t altitude_state,
                          int64_t update_index) {
  os_unfair_lock_lock(&qa_pen_lock);
  QaPenSample *slot = &qa_pen_ring[qa_pen_next];
  qa_pen_next = (qa_pen_next + 1) % QA_PEN_RING;
  slot->micros = micros;
  slot->update_index = update_index;
  slot->value = value;
  slot->altitude = altitude;
  slot->state = state;
  slot->altitude_state = altitude_state;
  slot->used = 1;
  os_unfair_lock_unlock(&qa_pen_lock);
}

// The newest record Flutter stamped [micros], or NULL. Call with the lock
// held.
static const QaPenSample *qa_pen_find(int64_t micros) {
  for (int n = 0; n < QA_PEN_RING; n++) {
    const int i = (qa_pen_next - 1 - n + QA_PEN_RING) % QA_PEN_RING;
    const QaPenSample *slot = &qa_pen_ring[i];
    if (slot->used && slot->micros == micros) {
      return slot;
    }
  }
  return NULL;
}

#if TARGET_OS_IOS

@interface QaPenLedger : NSObject
+ (void)noteTouches:(NSSet<UITouch *> *)touches;
+ (void)updateTouches:(NSSet<UITouch *> *)touches;
@end

@implementation QaPenLedger

+ (void)noteTouches:(NSSet<UITouch *> *)touches {
  for (UITouch *touch in touches) {
    if (touch.type != UITouchTypePencil) {
      continue;
    }
    const UITouchProperties awaited = touch.estimatedPropertiesExpectingUpdates;
    NSNumber *index = touch.estimationUpdateIndex;
    qa_pen_record(
        qa_pen_micros(touch.timestamp), touch.force,
        (awaited & UITouchPropertyForce) != 0 ? QA_PEN_ESTIMATED
                                              : QA_PEN_MEASURED,
        touch.altitudeAngle,
        (awaited & UITouchPropertyAltitude) != 0 ? QA_PEN_ESTIMATED
                                                 : QA_PEN_MEASURED,
        index != nil ? index.longLongValue : -1);
  }
}

+ (void)updateTouches:(NSSet<UITouch *> *)touches {
  for (UITouch *touch in touches) {
    NSNumber *index = touch.estimationUpdateIndex;
    if (index == nil) {
      continue;
    }
    // Only a property UIKit no longer means to update replaces an estimate.
    const UITouchProperties awaited = touch.estimatedPropertiesExpectingUpdates;
    const BOOL force = (awaited & UITouchPropertyForce) == 0;
    const BOOL altitude = (awaited & UITouchPropertyAltitude) == 0;
    const int64_t key = index.longLongValue;
    os_unfair_lock_lock(&qa_pen_lock);
    for (int i = 0; i < QA_PEN_RING; i++) {
      QaPenSample *slot = &qa_pen_ring[i];
      if (!slot->used || slot->update_index != key) {
        continue;
      }
      if (force && slot->state == QA_PEN_ESTIMATED) {
        slot->value = touch.force;
        slot->state = QA_PEN_MEASURED;
      }
      if (altitude && slot->altitude_state == QA_PEN_ESTIMATED) {
        slot->altitude = touch.altitudeAngle;
        slot->altitude_state = QA_PEN_MEASURED;
      }
    }
    os_unfair_lock_unlock(&qa_pen_lock);
  }
}

@end

#elif TARGET_OS_OSX

static id qa_pen_monitor = nil;

static void qa_pen_note_event(NSEvent *event) {
  const BOOL tablet = event.type == NSEventTypeTabletPoint ||
                      event.subtype == NSEventSubtypeTabletPoint;
  qa_pen_record(qa_pen_micros(event.timestamp), tablet ? event.pressure : 0,
                tablet ? QA_PEN_MEASURED : QA_PEN_NO_PRESSURE, 0,
                QA_PEN_UNREPORTED, -1);
}

static void qa_pen_install_monitor(void) {
  if (qa_pen_monitor != nil) {
    return;
  }
  const NSEventMask mask = NSEventMaskLeftMouseDown |
                           NSEventMaskLeftMouseDragged |
                           NSEventMaskLeftMouseUp | NSEventMaskTabletPoint;
  qa_pen_monitor =
      [NSEvent addLocalMonitorForEventsMatchingMask:mask
                                            handler:^NSEvent *(NSEvent *e) {
                                              qa_pen_note_event(e);
                                              return e;
                                            }];
}

#endif

// Starts whatever the platform needs to keep the ledger: the event monitor
// on macOS (installed on the main thread, where AppKit calls it); nothing
// on iOS, where the Runner writes. Safe to call again.
QA_EXPORT void qa_pen_ledger_start(void) {
#if TARGET_OS_OSX
  if ([NSThread isMainThread]) {
    qa_pen_install_monitor();
  } else {
    dispatch_async(dispatch_get_main_queue(), ^{
      qa_pen_install_monitor();
    });
  }
#endif
}

// What the ledger holds for the sample Flutter stamped [micros], newest
// record first: -1 when it has none, -2 while UIKit's force is still an
// estimate, -3 when the sample carries no pressure at all (a mouse on
// macOS); otherwise the value the platform reported — UIKit force on iOS,
// NSEvent pressure (0..1) on macOS.
QA_EXPORT double qa_pen_ledger_value(int64_t micros) {
  double result = -1;
  os_unfair_lock_lock(&qa_pen_lock);
  const QaPenSample *slot = qa_pen_find(micros);
  if (slot != NULL) {
    switch (slot->state) {
      case QA_PEN_ESTIMATED:
        result = -2;
        break;
      case QA_PEN_NO_PRESSURE:
        result = -3;
        break;
      default:
        result = slot->value;
        break;
    }
  }
  os_unfair_lock_unlock(&qa_pen_lock);
  return result;
}

// The pen's altitude for the sample Flutter stamped [micros], in radians
// from the surface (UIKit's altitudeAngle): -1 when the ledger has no
// record or the platform reports none, -2 while it is still UIKit's
// estimate.
QA_EXPORT double qa_pen_ledger_altitude(int64_t micros) {
  double result = -1;
  os_unfair_lock_lock(&qa_pen_lock);
  const QaPenSample *slot = qa_pen_find(micros);
  if (slot != NULL) {
    switch (slot->altitude_state) {
      case QA_PEN_ESTIMATED:
        result = -2;
        break;
      case QA_PEN_MEASURED:
        result = slot->altitude;
        break;
      default:
        break;
    }
  }
  os_unfair_lock_unlock(&qa_pen_lock);
  return result;
}
