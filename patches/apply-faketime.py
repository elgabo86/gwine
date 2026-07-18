#!/usr/bin/python3
"""Applique le faketime sur les sources wine stagées.
   Ne modifie que les fichiers non régénérés par make_requests.
   protocol.def est modifié → make_requests générera le reste automatiquement.
   Usage: python3 apply-faketime.py /path/to/wine/source"""

import sys, os

if len(sys.argv) < 2:
    sys.exit(1)

src = sys.argv[1]

# 1. protocol.def → ajouter @REQ(set_faketime) → make_requests générera tout
path = os.path.join(src, "server/protocol.def")
with open(path) as f:
    content = f.read()

if "set_faketime" not in content:
    content += """

@REQ(set_faketime)
    unsigned __int64 faketime;
@REPLY
@END
"""
    with open(path, "w") as f:
        f.write(content)
    print("  protocol.def OK")

# 2. fd.c → variable faketime + handler + modif current_time
path = os.path.join(src, "server/fd.c")
with open(path) as f:
    lines = f.readlines()

new_lines = []
added_faketime_var = False
for i, line in enumerate(lines):
    new_lines.append(line)
    if not added_faketime_var and "timeout_t monotonic_time;" in line:
        new_lines.append("static timeout_t faketime = 0;\n")
        added_faketime_var = True
    if "current_time = (timeout_t)now.tv_sec * TICKS_PER_SEC + now.tv_usec * 10 + ticks_1601_to_1970;" in line:
        new_lines[-1] = line.replace(
            "current_time = (timeout_t)now.tv_sec * TICKS_PER_SEC + now.tv_usec * 10 + ticks_1601_to_1970;",
            "current_time = (timeout_t)now.tv_sec * TICKS_PER_SEC + now.tv_usec * 10 + ticks_1601_to_1970 - faketime;"
        )

new_lines.append("""
DECL_HANDLER(set_faketime)
{
    faketime = ((current_time >> 32) - req->faketime) << 32;
}
""")

with open(path, "w") as f:
    f.writelines(new_lines)
print("  fd.c OK")

# 3. wine.inf.in → HwProfileGuid
path = os.path.join(src, "loader/wine.inf.in")
with open(path) as f:
    content = f.read()

if "HwProfileGuid" not in content:
    content += '\nHKLM,System\\CurrentControlSet\\Control\\IDConfigDB\\Hardware Profiles\\0001,"HwProfileGuid",,"{12345678-1234-1234-1234-123456789012}"\n'
    with open(path, "w") as f:
        f.write(content)
    print("  wine.inf.in OK")

print("faketime: done (protocol.def + fd.c + wine.inf.in)")
