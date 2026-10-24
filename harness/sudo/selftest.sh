#!/bin/bash
# Harmless: prints the uid it runs as. Used by install.sh and remote/mac-ready.sh to test the sudo rule.
echo "selftest uid=$(id -u)"
