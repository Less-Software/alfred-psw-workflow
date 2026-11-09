#!/bin/bash
# Alfred alternative action (⌥↩): copies the OTP code of the selected "username|domain" entry
source "$(dirname "$0")/apw_copy.sh"

copy_from_apw code OTP otp get "$DOMAIN"
