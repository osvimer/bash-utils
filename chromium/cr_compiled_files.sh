#!/bin/bash

VERSION=

FILENAME=cr_compiled_files

if [ "$1" == "cobalt" ]; then
    VERSION="mstar-armv7egl_qa"
    if [ -n "$2" ]; then
        VERSION=$2
    fi
else
    VERSION="Release"
    if [ -n "$1" ]; then
        VERSION=$1
    fi
fi

if [ ! -f "./out/$VERSION/build.ninja" ]; then
    echo "Please run this script in the src directory after first build"
else
    echo "Generate all compiled file list from ninja"
    cd ./out/$VERSION
    ninja -t commands | sed -n '/\.o$/p' | awk '{print $(NF-2)}' | sed '/\.a$/d' > ../../$FILENAME
    cd - > /dev/null

    #for those generated files, should add "out/$VERSION" prefix to the file path
    sed -i "s/^gen/out\/${VERSION}\/gen/" $FILENAME
    sed -i "s/^obj/out\/${VERSION}\/obj/" $FILENAME

    #trim the leading ../../
    sed -i 's/\.\.\/\.\.\///' $FILENAME

    echo
    echo "Done, generated file ./$FILENAME"
    wc -l $FILENAME
fi
