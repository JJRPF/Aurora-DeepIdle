#!/bin/bash
# GH-5: put the T6020 prep service and sleep hook back after the "no userspace prep" experiment.
set -e
[ -e /var/lib/deepidle/prep-off/90-t6020-s2r ] && mv /var/lib/deepidle/prep-off/90-t6020-s2r /usr/lib/systemd/system-sleep/90-t6020-s2r
systemctl enable s2r-t6020-prep.service
echo restored
