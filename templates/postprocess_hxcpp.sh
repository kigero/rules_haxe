#!/bin/bash

# Postprocess the HXCPP msvc setup files to run within the bazel/haxe nightmare.
# $1: haxelib_path
# $2: file to capture output in
set -e

export HAXELIB_PATH=`pwd`/$1
shift
OUTPUT=$1
shift

echo "PostProcess HXCPP" > $OUTPUT
for i in `find $HAXELIB_PATH|grep toolchain|grep msvc.*-setup.bat`; do
    echo "Updating $i" >> $OUTPUT
    sed -i 's/\%ProgramFiles(x86)\%/c:\\\\Program Files (x86)/g' $i
done
echo "Done" >> $OUTPUT