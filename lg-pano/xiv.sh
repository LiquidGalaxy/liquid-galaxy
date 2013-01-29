#!/bin/bash

FILES="$*"

DIAL=`which kdialog`
PARM="--getopenfilename $PWD"
if [ "x$DIAL" = "x" ]; then
  DIAL=`which zenity`
  PARM="--file-selection --title xiv"
fi
if [ "x$DIAL" = "x" ]; then
  DIAL=`which Xdialog`
  PARM="--fselect . 0 0"
fi

if [ "x$FILES" = "x" ]; then
FILES=`$DIAL $PARM`
fi

if [ "x$FILES" != "x" ]; then
xiv -browse "$FILES"
fi
