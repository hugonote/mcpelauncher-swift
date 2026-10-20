#pragma once

#include "import_table.hpp"

namespace macos_fixes::cond_wait_fix {

/**
 * Works around timed waits on condition variables set to CLOCK_MONOTONIC with
 * pthread_condattr_setclock. The mcpelauncher libc shim ignores that clock on
 * macOS, so the host reads a monotonic deadline as a 1970 wall-clock time, the
 * wait times out at once and the thread spins on a full core (NetherNet
 * Signal, Minecraft 1.26.52.3).
 *
 * A 20 ms monotonic wait is timed first; the workaround is installed only when
 * it returns early, so a runtime with a fixed shim is left alone. The game's
 * pthread_cond_timedwait import then moves deadlines older than 2001, which can
 * only be monotonic, to the same distance from the current wall-clock time.
 *
 * @return true when the shim needs the workaround and it is installed.
 */
bool install(const ImportTable &game);

}
