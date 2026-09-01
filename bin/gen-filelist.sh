#!/bin/bash

PROJDIR=$(realpath $(dirname "$0")/..)

cd $PROJDIR

fd -e lua -e c -E 'samples/**' > gtags.files
