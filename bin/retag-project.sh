#!/bin/bash

scriptdir=$(realpath $(dirname "$0"))

if [[ "$1" == -f ]]; then
    rm -f $scriptdir/../tags
fi

$scriptdir/gen-filelist.sh
$scriptdir/ctags-project.sh --no-gen-filelist
$scriptdir/gtags-project.sh --no-gen-filelist
