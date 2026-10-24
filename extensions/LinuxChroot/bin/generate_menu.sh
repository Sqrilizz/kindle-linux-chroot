#!/bin/sh
# Generates the KUAL menu at runtime (referenced with dynamic="true").
# Lists every rootfs image in /mnt/us/ and marks already-mounted ones,
# so the menu doubles as a status indicator.
#
# Output is a single JSON blob on stdout, KUAL reads everything it prints.

START='/bin/sh /mnt/us/extensions/LinuxChroot/bin/shell.sh'
STOP='/bin/sh /mnt/us/extensions/LinuxChroot/bin/stop.sh'
SSH='/bin/sh /mnt/us/start-ssh.sh'

printf '{\n  "items": [{\n    "name": "Linux Chroot",\n    "priority": 0,\n    "items": [\n'

FIRST=1
ISEQ=1
for f in /mnt/us/*.ext3; do
    [ -f "$f" ] || continue
    NAME=$(basename "$f" .ext3)
    # Escape JSON-special characters, drop other control junk
    SAFE=$(printf '%s' "$NAME" | sed 's/["\\]/ /g')
    LABEL=$SAFE
    if mount | grep " /tmp/${SAFE} " >/dev/null 2>&1; then
        LABEL="${SAFE} (mounted - stop first)"
    fi
    [ "$FIRST" -eq 1 ] || printf ',\n'
    printf '      {"name": "Start %s (%d)", "priority": %d, "action": "%s %s", "exitmenu": true}' \
        "$LABEL" "$ISEQ" "$ISEQ" "$START" "$f"
    FIRST=0
    ISEQ=$((ISEQ + 1))
done

[ "$FIRST" -eq 1 ] || printf ',\n'
printf '      {"name": "Start Terminal (interactive picker)", "priority": 90, "action": "%s", "exitmenu": true}' "$START"
printf ',\n      {"name": "Start SSH Server", "priority": 91, "action": "%s", "exitmenu": true}' "$SSH"
printf ',\n      {"name": "Stop Chroot", "priority": 92, "action": "%s", "exitmenu": true}' "$STOP"

printf '\n    ]\n  }]\n}\n'
