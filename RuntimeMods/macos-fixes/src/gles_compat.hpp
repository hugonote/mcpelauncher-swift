#pragma once

#include "import_table.hpp"

namespace macos_fixes::gles_compat {

/**
 * Lets the game render on an OpenGL ES 3.0 context, such as ANGLE's Metal
 * backend. Without ES 3.1 the renderer starts but draws nothing, so the game
 * is told it runs on ES 3.1 (GL_VERSION, GL_MINOR_VERSION, shading language
 * version) and the "#version 310 es" shaders it then sends are lowered to
 * "300 es"; outside Vibrant Visuals they use no ES 3.1 feature.
 *
 * GL_EXT_disjoint_timer_query is hidden because ANGLE Metal never completes
 * those queries; any other query still unavailable after a flush is reported
 * as available so the renderer cannot spin on it. Shaders and programs that
 * fail are logged. On any other context nothing is changed.
 *
 * The game resolves most GL functions through eglGetProcAddress, so both its
 * imports and that function are rebound.
 *
 * @return true when the GL imports are rebound.
 */
bool install(const ImportTable &game);

}
