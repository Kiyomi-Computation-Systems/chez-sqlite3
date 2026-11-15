#!/usr/bin/env python3
"""Compare utf8-dump.sps's answers with Python's decoder: for each line
(bytes in hex, then an offset or "ok"), bytes.decode('utf-8') either succeeds
(ok) or raises UnicodeDecodeError whose .start is the same offset.

    python3 -I .plans/research/m2-slice-1/utf8-check.py build/utf8-dump.txt
"""
import sys

agreed = 0
disagreed = []
with open(sys.argv[1]) as f:
    for line in f:
        hexbytes, answer = line.split()
        data = bytes.fromhex(hexbytes)
        try:
            data.decode("utf-8")
            expected = "ok"
        except UnicodeDecodeError as e:
            expected = str(e.start)
        if expected == answer:
            agreed += 1
        else:
            disagreed.append((hexbytes, answer, expected))
print("lines:", agreed + len(disagreed), "agreed:", agreed, "disagreed:", len(disagreed))
for row in disagreed[:20]:
    print("  bytes %s: scheme %s, python %s" % row)
sys.exit(1 if disagreed else 0)
