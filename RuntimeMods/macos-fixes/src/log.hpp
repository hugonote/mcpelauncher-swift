#pragma once

namespace macos_fixes::log {

/**
 * Writes one line to the game log with the "macos-fixes" tag.
 *
 * @param format printf format.
 */
void info(const char *format, ...) __attribute__((format(printf, 1, 2)));

/**
 * Same as info, with the error priority.
 *
 * @param format printf format.
 */
void error(const char *format, ...) __attribute__((format(printf, 1, 2)));

}
