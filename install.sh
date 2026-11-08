#!/bin/sh
# The one-shot setup, under the name get.sh and the older README use: everything is in setup.sh beside this file.
exec sh "$(dirname "$0")/setup.sh" "$@"
