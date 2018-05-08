#!/bin/bash
# duplicated_symbols_check.sh
# A tiny script to check all the duplicated symbols in binary or dynamic libraries
# contact: wangmingke@gmail.com

#TODO:

#usage example
# duplicated_symbol_check.sh folder

# uncomment for debugging
#set -xv

# the version of this script
VER=0.10
#echo "`basename $0` version $VER"

MY_NAME=$0
base_folder="."
out_file="symbols-duplicated.csv"
keep_all=0

usage()
{
    echo -e "\nThis script intends to search all duplicated symbols and their size info"
    echo "Usage : `basename $0` [-ah] [-o out_file] folder"
    echo "Note : version $VER"
    echo "    -o out_file        The file name to save duplicated symbols information, default symbols-duplicated.csv"
    echo "    foler              directoy to be checked, all binary and library will be scanned, binary and library symbols should not be stripped"
    echo "    -h                 Get help"
    echo "    -a                 Do not delete the temp file of all symbols"
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
    exit 1
fi

until [ $# -eq 0 ]
do
    param=$1
    if [ "${param:0:1}" = "-" ]; then
        param=${param:1}
        loop_end=0
        while [ -n "$param" ]
        do
            opt=${param:0:1}
            case $opt in
                o)
                    if [ -n "${param:1}" ]; then
                        out_file=${param:1}
                    else
                        out_file=$2
                        shift
                    fi
                    loop_end=1
                    ;;
                h)
                    #                        usage
                    #                        exit 0
                    ;;
                a)
                    keep_all=1
                    ;;
                *)
                    echo "Unknown option $opt"
                    usage
                    exit 1
                    ;;
            esac

            if [ $loop_end -eq 1 ]; then
                break
            else
                param=${param:1}
            fi
        done
    else
        base_folder=$1
    fi
    shift
done

CUR_P=`pwd`
SYMBOL_ALL=${CUR_P}/symbols.csv
SYMBOL_SORTED=${CUR_P}/symbols-sorted.csv
SYMBOL_DUP=${CUR_P}/${out_file}
#echo ${SYMBOL_ALL}
#echo ${SYMBOL_SORTED}
#echo ${SYMBOL_DUP}
elf_file_list=

function read_dir(){
    for f in `ls $1`
    do
        if [ -d $1"/"$f ]
        then
            read_dir $1"/"$f
        else
            file $1"/"$f | grep "ELF " > /dev/null 2>&1
            if [ $? -eq 0 ]; then
#                echo $1"/"$f
                elf_file_list=${elf_file_list}" "$1/$f
            fi
        fi
    done
}

echo "Scanning ELF binaries ..."
read_dir $base_folder
#echo $elf_file_list

#clear previous result
:>$SYMBOL_ALL

for file in $elf_file_list
do
#    echo $file
    echo "Export symbols from  $file ..."
    nm -B -td --print-size $file | awk '{if(NF==4){print f","$2","$3","$4}}' f=$file >> $SYMBOL_ALL
done

#remove unique symbols
echo "Sorting the symbols ..."
sort -k4 -t',' $SYMBOL_ALL > $SYMBOL_SORTED
echo "Searching the duplicated symbols and calculate duplicated size ..."
awk -F',' 'BEGIN{pre_line="";pre_symbol="";dup=0;dupsize=0;}
{if(pre_symbol==$4) {print pre_line;dup+=1;dupsize+=$2;} else { if(dup>0) {print pre_line;dup=0;}} pre_line=$0; pre_symbol=$4;}
END{if(dup>0) {print pre_line;} print "Total Duplicated Symbol Size: "dupsize" Bytes";}' $SYMBOL_SORTED > $SYMBOL_DUP

echo
tail -n1 $SYMBOL_DUP
echo

#insert csv header
sed -i '1 iLocation,Size,Type,Symbol' $SYMBOL_DUP

#delete tmp files
if [ $keep_all -eq 0 ]; then
    rm -rf $SYMBOL_ALL $SYMBOL_SORTED
fi
