#!/bin/bash

PROJDIR=$(realpath $(dirname "$0")/..)

cd $PROJDIR

if [[ "$1" == "--no-gen-filelist" ]]; then
    shift
else
    ./bin/gen-filelist.sh
fi

if [[ $# -eq 0 ]]; then
    update-ctags tags < gtags.files
else
    update-ctags tags "$@"
fi
