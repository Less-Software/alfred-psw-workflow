#!/bin/bash
# Alfred action (↩): copies the password of the selected "username|domain" entry
source "$(dirname "$0")/apw_copy.sh"

copy_from_apw password Password pw get "$DOMAIN" "$USERNAME"
