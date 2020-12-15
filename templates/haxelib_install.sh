#!/bin/bash

# An attempt to duplicate the haxelib installation process using a bash script, as `haxelib install` is just too 
# unreliable on windows within the shell launched by bazel.
# $1: neko_dir or .
# $2: haxe_dir or .
# $3: haxelib_path
# $4: WIN or LIN
# $5: file to capture output in
# $6: lib
# $7: version

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

# On Windows+cygwin the haxelib path has to actually be the windows path, as haxelib spawns a windows command shell.  
# cmd->bazel->bash->haxelib->cmd - fantastic.
if [[ "WIN" == "$1" ]]; then
    export HAXELIB_PATH=`cygpath -w $LIN_HAXELIB_PATH`
else
    export HAXELIB_PATH=$LIN_HAXELIB_PATH
fi
shift

OUTPUT=`pwd`/$1
shift

# Haxelib uses the dotted form of libs and versions for user facing things, but the comma form for internal things.
DOTTED_LIB=$1
COMMA_LIB=${DOTTED_LIB//./,}
shift

DOTTED_VERSION=$1
COMMA_VERSION=${DOTTED_VERSION//./,}

# It is all too easy for bazel to try launching multiple installation processes at once.  This can be managed somewhat
# effectively within bazel itself through the use of dependant files, but that gets REALLY hard when you start dealing
# with dependant haxe projects, where bazel will try to kick off multiple installations of a haxelib in both the primary
# and dependant projects.  Doing some locking here just to ensure that the processes can't interfere with themselves
# seems like a reasonable compromise.  It lets bazel launch the processes, but doesn't allow the install code to run in
# parallel.  Since there's a check early to see if the lib is already installed, it should return pretty quickly if two
# installs get kicked off at once.
ME=`basename "$0"`;
LCK="/tmp/${ME}.LCK";
exec 8>$LCK;
flock -x 8;

# See if this version is already installed.
haxelib path $DOTTED_LIB:$DOTTED_VERSION > $OUTPUT || EXIT_CODE=$?
if [[ "$EXIT_CODE" -eq 0 ]]; then
    exit 0
fi

# It's not, so install it into the common haxelib directory.
cd $LIN_HAXELIB_PATH

# Create the comma version of the library name if needed.
mkdir -p $COMMA_LIB
cd $COMMA_LIB
    
if [[ $DOTTED_VERSION == "git:"* ]]; then
    git clone ${DOTTED_VERSION:4} git

    # If there is no .current file, write the git version to that file.
    if [ ! -f .current ]; then
        echo git > .current
    fi
else
    # Get rid of any bad files using the comma version of the version, perhaps left over from a failed install.
    rm -rf $COMMA_VERSION  

    # Get the zip file from the haxelib repo.
    echo "Getting lib: curl -s -L -o lib.zip https://lib.haxe.org/files/3.0/$COMMA_LIB-$COMMA_VERSION.zip" >> $OUTPUT
    curl -s -L -o lib.zip https://lib.haxe.org/files/3.0/$COMMA_LIB-$COMMA_VERSION.zip

    # Unzip it.  On windows unzip sometimes has issues with duplicate file names - not sure why - so ignore them if they
    # occur, hoping that a later step will catch the error if there's a real problem.
    echo "Inflating lib." >> $OUTPUT
    unzip -qq lib.zip || true
    rm lib.zip

    # Store the haxelib contents in the comma version subdirectory.  It seems that the haxelib.json file is always in this
    # subdirectory, so use that as a marker to see where things need to be moved.
    echo "Moving contents to versioned subdirectory." >> $OUTPUT
    JSON_PATH=`find | grep haxelib.json`
    JSON_PATH=`dirname $JSON_PATH`
    echo "JSON_PATH = $JSON_PATH" >> $OUTPUT
    if [[ "." == "$JSON_PATH" ]]; then
        mkdir "$COMMA_VERSION"
        ls | grep -v "$COMMA_VERSION" | xargs mv -t "$COMMA_VERSION"
    else
        mv $JSON_PATH "$COMMA_VERSION"
    fi

    # If there is no .current file, write the current install version to that file.
    if [ ! -f .current ]; then
        echo $DOTTED_VERSION > .current
    fi
fi

# Finally write out the path to the output file.  If the haxelib failed to install for some reason this should fail,
# failing the process as a whole.
haxelib path $DOTTED_LIB:$DOTTED_VERSION > $OUTPUT