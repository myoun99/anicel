// Several callers at once on the engine (card
// clip-import-hangs-on-three-samples, 2026-10-23).
//
// Every isolate that loads the engine calls it from a thread of its own,
// and the clip import draws vector layers on several at once. The pool was
// one job slot and one set of wake-ups for the process: two callers at once
// overwrote each other's job, one waited for a wake-up nobody would send,
// and three .clip samples never finished opening. Everything else that runs
// the engine here — the parity suites, the canvas — calls it from one
// thread, so nothing else can see two callers at once.
//
// It includes the translation unit rather than linking it, because the pool
// is static.
//
// ↩️The callers composed a fill's raster and flooded it too, and the
// flood's one wave arena was held by one of them at a time, until the fill
// went to the GPU engine (ABI 78). What they run through the pool now is a
// stamp laid over many tiles — the batch a vector layer's strokes land by.

#include "qa_engine.c"

#include <stdio.h>

#if defined(_WIN32)
typedef volatile LONG pool_test_count;

static void pool_test_add(pool_test_count* count) {
  InterlockedIncrement(count);
}

static int32_t pool_test_read(pool_test_count* count) {
  return (int32_t)InterlockedCompareExchange(count, 0, 0);
}

static void pool_test_nap(void) {
  Sleep(10);
}
#else
typedef int32_t pool_test_count;

static void pool_test_add(pool_test_count* count) {
  __atomic_fetch_add(count, 1, __ATOMIC_SEQ_CST);
}

static int32_t pool_test_read(pool_test_count* count) {
  return __atomic_load_n(count, __ATOMIC_SEQ_CST);
}

static void pool_test_nap(void) {
  usleep(10000);
}
#endif

enum {
  CALLERS = 6,
  ROUNDS = 200,
  // Enough items that every worker takes some.
  ITEMS = 48,
  // 8 x 4 tiles of 32 under one stamp, so one batch spans the pool.
  TILE = 32,
  TILES_X = 8,
  TILES_Y = 4,
  TILE_COUNT = TILES_X * TILES_Y,
  STAMP_W = TILE * TILES_X,
  STAMP_H = TILE * TILES_Y,
  // A hang fails the run instead of stalling it: 60 s, in naps of 10 ms.
  DEADLINE_NAPS = 6000,
};

typedef struct {
  pool_test_count hits[ITEMS];
} pool_test_board;

static void pool_test_hit(int32_t item, void* context) {
  pool_test_board* board = (pool_test_board*)context;
  // Long enough that the callers' calls overlap.
  volatile uint32_t spin = 0;
  for (uint32_t i = 0; i < 4000; i += 1) {
    spin += i;
  }
  pool_test_add(&board->hits[item]);
}

static pool_test_count g_started;
static pool_test_count g_in_company;

// Waits, up to 2 s, for the other item to start beside this one.
static void pool_test_wait_for_company(int32_t item, void* context) {
  (void)item;
  (void)context;
  pool_test_add(&g_started);
  for (int nap = 0; nap < 200 && pool_test_read(&g_started) < 2; nap += 1) {
    pool_test_nap();
  }
  if (pool_test_read(&g_started) == 2) {
    pool_test_add(&g_in_company);
  }
}

// Whether this machine should spread a call: it has the processors, and
// nobody set the thread count. Asked of the machine rather than of the
// pool, because a pool that never started has no workers to report.
static int pool_test_should_spread(void) {
  if (getenv("QA_ENGINE_THREADS") != NULL) {
    return 0;
  }
#if defined(_WIN32)
  SYSTEM_INFO info;
  GetSystemInfo(&info);
  return info.dwNumberOfProcessors >= 2;
#else
  return sysconf(_SC_NPROCESSORS_ONLN) >= 2;
#endif
}

// Whether a call alone is spread across the workers: on one thread the
// first of two items waits out its 2 s alone, and only the second finds
// company. Results are the same either way — this is the pool's one job.
static int pool_test_spreads(void) {
  g_started = 0;
  g_in_company = 0;
  qa_pool_run(pool_test_wait_for_company, NULL, 2);
  return pool_test_read(&g_in_company) == 2;
}

// Each of this call's items ran, once, with this call's context.
static int pool_test_own_items(void) {
  pool_test_board board;
  memset((void*)&board, 0, sizeof(board));
  qa_pool_run(pool_test_hit, &board, ITEMS);
  for (int32_t i = 0; i < ITEMS; i += 1) {
    if (pool_test_read(&board.hits[i]) != 1) {
      return 0;
    }
  }
  return 1;
}

typedef struct {
  uint8_t stamp[STAMP_W * STAMP_H * 4];
  double opacity;
  uint8_t alone[TILE_COUNT][TILE * TILE * 4];
  uint8_t tiles[TILE_COUNT][TILE * TILE * 4];
} pool_test_stamp;

static pool_test_stamp g_stamps[CALLERS];

static uint32_t pool_test_next_byte(uint32_t* state) {
  *state = *state * 1664525u + 1013904223u;
  return *state >> 24;
}

// A stamp of the caller's own noise, as opaque as the caller's own: no two
// callers lay the same tiles.
static void pool_test_set_stamp(int caller) {
  pool_test_stamp* s = &g_stamps[caller];
  uint32_t state = 7u + (uint32_t)caller;
  for (int32_t i = 0; i < STAMP_W * STAMP_H * 4; i += 1) {
    s->stamp[i] = (uint8_t)pool_test_next_byte(&state);
  }
  s->opacity = 0.4 + 0.1 * caller;
}

// The caller's stamp laid over every tile of `tiles`, each 0x5A in every
// byte before it, in one batch.
static void pool_test_stamp_into(pool_test_stamp* s,
                                 uint8_t tiles[TILE_COUNT][TILE * TILE * 4]) {
  qa_tile_span spans[TILE_COUNT];
  uint8_t changed[TILE_COUNT];
  memset(spans, 0, sizeof(spans));
  memset(tiles, 0x5A, (size_t)TILE_COUNT * TILE * TILE * 4);
  for (int32_t row = 0; row < TILES_Y; row += 1) {
    for (int32_t column = 0; column < TILES_X; column += 1) {
      qa_tile_span* span = &spans[row * TILES_X + column];
      span->tile_pixels = tiles[row * TILES_X + column];
      span->tile_left = column * TILE;
      span->tile_top = row * TILE;
      span->span_left = column * TILE;
      span->span_right_exclusive = (column + 1) * TILE;
      span->span_top = row * TILE;
      span->span_bottom_exclusive = (row + 1) * TILE;
    }
  }
  qa_stamp_blend_tiles(spans, TILE_COUNT, TILE, s->stamp, STAMP_W, 0, 0,
                       s->opacity, 0, changed);
}

typedef struct {
  int index;
  int failures;
  pool_test_count* finished;
} pool_test_caller;

static void pool_test_fail(pool_test_caller* caller, int32_t round,
                           const char* what) {
  if (caller->failures < 3) {
    printf("FAIL caller %d, round %d: %s\n", caller->index, round, what);
  }
  caller->failures += 1;
}

static void pool_test_run_caller(pool_test_caller* caller) {
  pool_test_stamp* s = &g_stamps[caller->index];
  for (int32_t round = 0; round < ROUNDS; round += 1) {
    if (!pool_test_own_items()) {
      pool_test_fail(caller, round, "its pool items did not each run once");
    }
    pool_test_stamp_into(s, s->tiles);
    if (memcmp(s->tiles, s->alone, sizeof(s->alone)) != 0) {
      pool_test_fail(caller, round, "its tiles are not the ones laid alone");
    }
  }
  pool_test_add(caller->finished);
}

#if defined(_WIN32)
static unsigned __stdcall pool_test_thread(void* argument) {
  pool_test_run_caller((pool_test_caller*)argument);
  return 0;
}
#else
static void* pool_test_thread(void* argument) {
  pool_test_run_caller((pool_test_caller*)argument);
  return NULL;
}
#endif

int main(void) {
  int failures = 0;

  // Alone first: what each caller must get when nobody else is running.
  const int should_spread = pool_test_should_spread();
  if (should_spread && !pool_test_spreads()) {
    printf("FAIL: a call alone ran on one thread, with %d workers\n",
           g_pool.worker_count);
    failures += 1;
  }
  for (int caller = 0; caller < CALLERS; caller += 1) {
    pool_test_set_stamp(caller);
    pool_test_stamp_into(&g_stamps[caller], g_stamps[caller].alone);
  }
  if (memcmp(g_stamps[0].alone, g_stamps[1].alone,
             sizeof(g_stamps[0].alone)) == 0) {
    printf("FAIL: two callers' tiles alone are the same tiles\n");
    failures += 1;
  }

  pool_test_count finished = 0;
  pool_test_caller callers[CALLERS];
#if defined(_WIN32)
  HANDLE threads[CALLERS];
#else
  pthread_t threads[CALLERS];
#endif
  for (int i = 0; i < CALLERS; i += 1) {
    const pool_test_caller caller = {i, 0, &finished};
    callers[i] = caller;
#if defined(_WIN32)
    threads[i] = (HANDLE)_beginthreadex(NULL, 0, pool_test_thread,
                                        &callers[i], 0, NULL);
#else
    pthread_create(&threads[i], NULL, pool_test_thread, &callers[i]);
#endif
  }
  for (int nap = 0; pool_test_read(&finished) < CALLERS; nap += 1) {
    if (nap == DEADLINE_NAPS) {
      printf("FAIL: %d of %d callers at once never finished\n",
             CALLERS - pool_test_read(&finished), CALLERS);
      fflush(stdout);
      exit(1);
    }
    pool_test_nap();
  }
  for (int i = 0; i < CALLERS; i += 1) {
#if defined(_WIN32)
    WaitForSingleObject(threads[i], INFINITE);
    CloseHandle(threads[i]);
#else
    pthread_join(threads[i], NULL);
#endif
    failures += callers[i].failures;
  }

  // Given back: the next caller has the pool to itself.
  if (should_spread && !pool_test_spreads()) {
    printf("FAIL: a call alone, after the callers, ran on one thread\n");
    failures += 1;
  }
  pool_test_stamp* s = &g_stamps[0];
  pool_test_stamp_into(s, s->tiles);
  if (memcmp(s->tiles, s->alone, sizeof(s->alone)) != 0) {
    printf("FAIL: tiles laid alone, after the callers, are not the ones "
           "before\n");
    failures += 1;
  }

  if (failures == 0) {
    printf("qa_engine_pool: all passed (%d workers)\n", g_pool.worker_count);
  }
  return failures == 0 ? 0 : 1;
}
