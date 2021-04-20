#!/bin/bash

# Copy HXCPP include files.
# $1: haxelib_path
# $2: path to copy to
# $3: file to capture output in
set -e

export HAXELIB_PATH=`pwd`/$1
shift
OUT_DIR=$1
shift
OUTPUT=$1
shift

echo "Copy HXCPP Includes" > $OUTPUT
HXCPP_PATH=`haxelib libpath hxcpp`
cp -r $HXCPP_PATH/include/* $OUT_DIR
echo "Done" >> $OUTPUT
