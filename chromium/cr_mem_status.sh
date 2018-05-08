#!/bin/sh
# cr_mem_stat.sh
# A tiny script to use showmap/pmap/procrank to get the physical memory usage of a program
# record the memory usage data into a formatted csv file

#TODO:

#usage example
# cr_mem_stat.sh -t showmap -p chromium -o App_Netrange log_before_enter

# uncomment for debugging
#set -xv

# the version of this script
VER=0.20
#echo "`basename $0` version $VER"
#echo

MY_NAME=$0
program="chromium"
mem_tool="showmap"
#PS_OPT="-w"
PS_OPT=""
case_name="log_case"
out_file="app_mem"
SAVE_LOGS=0
SAVE_CSV=0

usage()
{
    echo -e "\nThis script intends to get total physical memory usage of a program by curtain memory check tool"
    echo "Usage : `basename $0` [-t showmap|pmap|procrank] [-p program] [-o out_file] [-l] case_name"
    echo "Note : version $VER"
    echo "    -t showmap|pmap|procrank  the memory tool to be used, currently support showmap/pmap/procrank"
    echo "    -p program                The process name need to be analyzed, if not specified, then default to $program"
    echo "    -o out_file               The file name to save the total PSS information of each test. Please be noted that the new result will append to the end of file"
    echo "    case_name                 The name of the log to be saved."
    echo "    -l                        save logs."
    echo "    -h                        Get help"
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
                t)
                    if [ -n "${param:1}" ]; then
                        mem_tool=${param:1}
                    else
                        mem_tool=$2
                        shift
                    fi
                    loop_end=1
                    if [ "$mem_tool" != "showmap" ] && [ "$mem_tool" != "pmap" ] && [ "$mem_tool" != "procrank" ]; then
                        echo "Unknown memory tool, set default to showmap"
                        mem_tool="showmap"
                    fi
                    ;;
                p)
                    if [ -n "${param:1}" ]; then
                        program=${param:1}
                    else
                        program=$2
                        shift
                    fi
                    loop_end=1
                    ;;
                o)
                    if [ -n "${param:1}" ]; then
                        out_file=${param:1}
                    else
                        out_file=$2
                        shift
                    fi
                    loop_end=1
                    SAVE_CSV=1
                    ;;
                l)
                    SAVE_LOGS=1
                    ;;
                h)
                    #                        usage
                    #                        exit 0
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
        case_name=$param
    fi
    shift
done

#echo "Getting all PIDs of $program..."


pids=`ps $PS_OPT | grep -F "$program" | grep -v "grep" | grep -v "$MY_NAME" | awk '{print $1}'`
if [ -z "$pids" ]; then
    echo "!!!!!! $program is not running !!!!!!"
    exit 1
fi

if [ "$mem_tool" = "procrank" ]; then
    procrank > /dev/null
    if [ $? -ne 0 ]; then
        echo "procrank not found, please install procrank and export the right PATH to it."
        exit 1
    fi
    pids=`procrank | grep -E "${program}|self" | awk '{print $1}'`
fi

# generate csv output file name
out_file=${out_file}_${mem_tool}

# Create the outpt file if it hasn't been created
if [ $SAVE_CSV -eq 1 ]; then
    if [ ! -f "./${out_file}.csv" ]; then
        echo "Create out put file ${out_file}.csv"
        header="UseCase"
        for pid in $pids
        do
            header="${header}, PID=$pid [K]"
        done
        echo "${header}, Total [K]" > ./${out_file}.csv
    fi
fi

# showmap
if [ "$mem_tool" = "showmap" ]; then
    showmap > /dev/null 2&>1
    if [ $? -ne 0 ] && [ $? -ne 1 ]; then
        echo "showmap not found, please install showmap and export the right PATH to it."
        exit 1
    fi

    pss_line=$case_name
    pss_total=0

    for pid in $pids
    do
        log_name=${out_file}_${case_name}_${pid}.log
        showmap $pid 2>/dev/null > $log_name
        pss=`tail -1 $log_name | awk '{print $3}'`
        pss_line="${pss_line}, $pss"
        pss_total=$(($pss_total+$pss))
    done
    echo "$pss_line, $pss_total"

    # save pss data into csv file
    if [ $SAVE_CSV -eq 1 ]; then
        echo "$pss_line, $pss_total" >> ./${out_file}.csv
    fi

    # remove log files if we don't need
    if [ $SAVE_LOGS -eq 0 ]; then
        rm -f ${out_file}_${case_name}_* >/dev/null
    fi

    exit 0
fi


# pmap
if [ "$mem_tool" = "pmap" ]; then
    pmap >/dev/null 2&>1
    if [ $? -eq 0 ] && [ $? -eq 1 ]; then
        busybox | grep pmap >/dev/null
        if [ $? -ne 0 ]; then
            echo "Can't find pmap, make sure pmap was installed"
            exit 1
        fi
    fi
    pss_line=$case_name
    pss_total=0

    for pid in $pids
    do
        log_name=${out_file}_${case_name}_${pid}.log
        pmap -x $pid > $log_name
        pss=`tail -1 $log_name | awk '{print $3}'`
        pss_line="${pss_line}, $pss"
        pss_total=$(($pss_total+$pss))
    done

    echo "$pss_line, $pss_total"

    # save pss data into csv file
    if [ $SAVE_CSV -eq 1 ]; then
        echo "$pss_line, $pss_total" >> ./${out_file}.csv
    fi

    # remove log files if we don't need
    if [ $SAVE_LOGS -eq 0 ]; then
        rm -f ${out_file}_${case_name}_* >/dev/null
    fi

    exit 0
fi

# procrannk
if [ "$mem_tool" = "procrank" ]; then
    log_name=${out_file}_${case_name}.log
    procrank > $log_name
    procrank_values=`grep -E "${program}|self"  $log_name | awk '{print $4}'`
    pss_line=$case_name
    pss_total=0

    for val in $procrank_values
    do
        pss=${val%?}
        pss_line="${pss_line}, $pss"
        pss_total=$(($pss_total+$pss))
    done
    echo "$pss_line, $pss_total"

    # save pss data into csv file
    if [ $SAVE_CSV -eq 1 ]; then
        echo "$pss_line, $pss_total" >> ./${out_file}.csv
    fi

    # remove log files if we don't need
    if [ $SAVE_LOGS -eq 0 ]; then
        rm -f $log_name >/dev/null
    fi

    exit 0
fi
