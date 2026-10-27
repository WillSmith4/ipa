"""Compile the actual input queue functions with a paused deterministic sender."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as temporary:
    directory = Path(temporary)
    generated = directory / "OrderedInputStream.c"
    subprocess.run([sys.executable, str(root / "BuildScripts/prepare-gesture-input.py"), str(generated)], check=True)
    source = generated.read_text(encoding="utf-8")
    start = source.index("typedef struct _PACKET_HOLDER {")
    end = source.index("} PACKET_HOLDER, *PPACKET_HOLDER;", start) + len("} PACKET_HOLDER, *PPACKET_HOLDER;")
    (directory / "MousePacketHolder.inc").write_text(source[start:end], encoding="utf-8")
    methods = []
    for name in ["LiSendMousePositionEvent", "LiSendMouseButtonEvent", "LiSendMousePositionEventOrdered"]:
        start = source.index("int " + name + "(")
        end = source.index("\n}", start) + 2
        methods.append(source[start:end])
    (directory / "MousePositionMethods.inc").write_text("\n".join(methods), encoding="utf-8")
    start = source.index("else if (holder->packet.header.magic == LE32(MOUSE_MOVE_ABS_MAGIC)")
    end = source.index("\n        // If it's a pen packet", start)
    (directory / "MousePositionSendBranch.inc").write_text(source[start:end], encoding="utf-8")
    start = source.index("bool orderedPosition =")
    end = source.index("\n        freePacketHolder(holder);", start)
    (directory / "MousePositionFlush.inc").write_text(source[start:end], encoding="utf-8")
    binary = directory / ("mouse-tests.exe" if os.name == "nt" else "mouse-tests")
    subprocess.run([os.environ.get("CC", "cc"), "-std=c11", "-Wall", "-Wextra", "-Werror",
                    "-I", str(directory), "-I", str(root / "moonlight-common/moonlight-common-c/src"),
                    str(root / "Tests/OrderedMousePositionTests.c"), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
