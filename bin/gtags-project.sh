#!/bin/bash
# Generates tag files for use with GNU Global

PROJDIR=$(realpath $(dirname "$0")/..)

cd $PROJDIR

if [[ "$1" == "--no-gen-filelist" ]]; then
    shift
else
    ./bin/gen-filelist.sh
fi

gtags -vi --sqlite3
