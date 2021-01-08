#!/bin/bash

# Set up the envrionment for running haxe.
# $1: neko_dir or .
# $2: haxe_dir or .
# $3: haxelib_path
# $4: WIN or LIN
# $5: file to capture output in
# Rest of arguments are command to run
set -e

if [[ "." != "$1" ]]; then
    export PATH=`pwd`/$1:$PATH
fi
shift

if [[ "." != "$1" ]]; then
    export PATH=`pwd`/$1:$PATH
fi
shift

export LIN_HAXELIB_PATH=`pwd`/$1
shift

# On Windows+[cygwin|mingw] the haxelib path has to actually be the windows path, as haxelib spawns a windows command shell.  
# cmd->bazel->bash->haxelib->cmd - fantastic.
if [[ "WIN" == "$1" ]]; then
    export HAXELIB_PATH=`cygpath -w $LIN_HAXELIB_PATH`
else
    export HAXELIB_PATH=$LIN_HAXELIB_PATH
fi
shift

OUTPUT=$1
shift

$@ > $OUTPUT