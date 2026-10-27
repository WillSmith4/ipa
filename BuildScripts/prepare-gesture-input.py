"""Build an input-stream copy with opt-in ordered positions; keep the submodule intact."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
source_dir = root / "moonlight-common/moonlight-common-c/src"
source = (source_dir / "InputStream.c").read_text(encoding="utf-8")


def replace_once(old, new):
    global source
    if source.count(old) != 1:
        raise RuntimeError("InputStream.c changed; review ordered mouse position integration: " + old)
    source = source.replace(old, new, 1)


replace_once('#include "Limelight-internal.h"',
             '#include "' + (source_dir / "Limelight-internal.h").as_posix() + '"')
replace_once("    uint8_t channelId;", "    uint8_t channelId;\n    bool absolutePositionIsOrdered;")
replace_once("else if (holder->packet.header.magic == LE32(MOUSE_MOVE_ABS_MAGIC)) {",
             "else if (holder->packet.header.magic == LE32(MOUSE_MOVE_ABS_MAGIC) && !holder->absolutePositionIsOrdered) {")
replace_once("        holder->packet.mouseMoveAbs.unused = 0;",
             "        holder->absolutePositionIsOrdered = false;\n        holder->packet.mouseMoveAbs.unused = 0;")
replace_once("if (!sendInputPacket(holder, LbqGetItemCount(&packetQueue) > 0)) {",
             """// Ordered swipe positions must reach the host without waiting for
        // the following press/move to flush the transport's outgoing batch.
        bool orderedPosition = holder->packet.header.magic == LE32(MOUSE_MOVE_ABS_MAGIC) && holder->absolutePositionIsOrdered;
        if (!sendInputPacket(holder, !orderedPosition && LbqGetItemCount(&packetQueue) > 0)) {""")
source += "\n" + (root / "moonlight-common/OrderedMousePosition.c.inc").read_text(encoding="utf-8")
output = Path(sys.argv[1])
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(source, encoding="utf-8")
