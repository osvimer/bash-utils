#!/bin/bash
# generate cscope files list

VERSION="Release"

echo "Generate file list to be indexed..."

if [ ! -f "./out/$VERSION/build.ninja" ]; then
    echo "Please run this script in the src directory after first build"
    exit 1
else
    echo "Generate compiling list from ninja"
    cd ./out/$VERSION
    ninja -t deps | sed '/^obj/d' | sed '/^$/d' | sort -u | sed 's/^[ \t]*//' > ../../cscope.files
    cd - > /dev/null

    #for those generated files, should add "out/$VERSION" prefix to the file path
    sed -i "s/^gen/out\/${VERSION}\/gen/" cscope.files
    sed -i "s/^obj/out\/${VERSION}\/obj/" cscope.files

    #trim the leading ../../
    sed -i 's/\.\.\/\.\.\///' cscope.files

    #TODO remove un-intreresting folders
fi

echo "cscope indexing..."
cscope -b -q -k

echo "Done, have fun!"
