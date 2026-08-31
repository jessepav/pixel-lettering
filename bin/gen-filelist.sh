#!/bin/bash

PROJDIR=$(realpath $(dirname "$0")/..)

cd $PROJDIR

fd -g '*.lua' > gtags.files
