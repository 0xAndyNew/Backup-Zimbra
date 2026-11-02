#!/bin/sh
set -e
if ! (getent passwd zimbra || id zimbra) >/dev/null 2>&1; then
    echo "ERROR: System user 'zimbra' does not exist. Install Zimbra Collaboration before installing zimbra-backup." >&2
    exit 1
fi
exit 0
