# cr_monitor.sh
# a tiny tool to monitor the memory and cpu loading of a specific program
# record the memory and cpu usage data into a formatted csv file

#TODO:

#usage example
# cr_monitor.sh -rv -i3 chromium

# uncomment for debugging
#set -xv

# the version of this script
VER=0.92
echo "`basename $0` version $VER"
echo

MY_NAME=$0
DEFAULT_INTERVAL=5000
DEFAULT_PROGRAM="chromium"
GET_BK_MEM=0
CPU_LOAD=0
CPU_ONLY=0
M_DATA_STK=0
M_PSS=0
M_CBS=0
CONSOLE_PRINT=0
PRINT_ALL=0
GET_TOTAL=0
interval=$DEFAULT_INTERVAL
program=$DEFAULT_PROGRAM
HAS_GETOPTS=0
OUT_FILE="./cr_monitor"

#detect if target shell has getopts, some embeded system use busybox, may hasn't getopts
getopts > /dev/null 2&>1
if [ $? -eq 0 ]; then
    HAS_GETOPTS=1
fi

usage()
{
    echo -e "\nUsage : `basename $0` [-BtrcpavmTh] [-o out_file] [-i interval] [-I init_free] [program]"
    echo "Note :"
    echo "    program         The process name need to be monitered, if not specified, then monitor default program $program"
    echo "    -B              Get the memory usage when $program running background, this option should be used after TV reboot without any further operation"
    echo "    -r              monitor PSS memory usage of each process"
    echo "    -c              monitor cpu usage and cpu loading, by default, monitor memory usage only"
    echo "    -C              monitor cpu usage only"
    echo "    -p              print monitoring info in console"
    echo "    -a              print all command output"
    echo "    -v              monitor VmData and VmStk of each process"
    echo "    -m              monitor free, cached, buffered and shmem"
    echo "    -T              print total of all process with same program name"
    echo "    -i interval     The interval time (in millisecond) of checking, if no interval specified, use default $DEFAULT_INTERVAL milliseconds"
    echo "    -o out_file     The output file pathname, default is $OUT_FILE in current work directory"
    echo "    -h              get help"
    echo ""
}

if [ $HAS_GETOPTS -eq 1 ]; then
    while getopts tvaTpCrhcmBo:i:I: OPTION
    do
        case $OPTION in
            i) interval=$OPTARG
                ;;
            o) OUT_FILE=$OPTARG
                ;;
            v) M_DATA_STK=1
                ;;
            a) PRINT_ALL=1
                ;;
            T) GET_TOTAL=1
                ;;
            p) CONSOLE_PRINT=1
                ;;
            c) CPU_LOAD=1
                ;;
            C) CPU_ONLY=1
                ;;
            m) M_CBS=1
                ;;
            B) GET_BK_MEM=1
                ;;
            r) M_PSS=1
                ;;
            h)
                ;;
            *) usage
                exit 1
                ;;
        esac
    done

    shift `expr $OPTIND - 1`
    #echo "$@"

    if [ -n "$1" ]; then
        program=$1
    fi
else
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
                    i)
                        if [ -n "${param:1}" ]; then
                            interval=${param:1}
                        else
                            interval=$2
                            shift
                        fi
                        loop_end=1
                        ;;
                    o)
                        if [ -n "${param:1}" ]; then
                            OUT_FILE=${param:1}
                        else
                            OUT_FILE=$2
                            shift
                        fi
                        loop_end=1
                        ;;
                    v) M_DATA_STK=1
                        ;;
                    a) PRINT_ALL=1
                        ;;
                    T) GET_TOTAL=1
                        ;;
                    p) CONSOLE_PRINT=1
                        ;;
                    c) CPU_LOAD=1
                        ;;
                    C) CPU_ONLY=1
                        ;;
                    m) M_CBS=1
                        ;;
                    B) GET_BK_MEM=1
                        ;;
                    r) M_PSS=1
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
            program=$param
        fi
        shift
    done
fi

#debug parameters only
#echo GET_BK_MEM $GET_BK_MEM
#echo CPU_LOAD $CPU_LOAD
#echo M_DATA_STK $M_DATA_STK
#echo M_PSS $M_PSS
#echo M_CBS $M_CBS
#echo CONSOLE_PRINT $CONSOLE_PRINT
#echo PRINT_ALL $PRINT_ALL
#echo GET_TOTAL $GET_TOTAL
#echo INTERVAL $interval
#echo PROGRAM $program
#echo HAS_GETOPTS $HAS_GETOPTS
#echo OUT_FILE $OUT_FILE
#exit 0

OUT_FILE=${OUT_FILE}_`date +%F-%H%M%S`.csv
#PS_OPT="-w"
PS_OPT=""

# We use pmap to get PSS of each process, check if pmap available
pmap >/dev/null 2&>1
if [ $? -ne 0 ] && [ $? -ne 1 ]; then
    busybox | grep pmap >/dev/null
    if [ $? -ne 0 ]; then
        echo "Can't find pmap, make sure pmap was installed"
        exit 1
    fi
fi

if [ $GET_BK_MEM -eq 1 ]; then
    pids=`ps $PS_OPT | grep -F "$program" | grep -v "grep" | grep -v "$MY_NAME" | awk '{print $1}'`
    if [ -z "$pids" ]; then
        echo "!!!!!! $program is not running !!!!!!"
        exit 1
    fi

    bk_mem=0

    for pid in $pids
    do
        pss=`pmap -x $pid | tail -1 | awk '{print $3}'`
        bk_mem=$(($bk_mem+$pss))
    done

    echo "****** [$program] occupy [$bk_mem] KB memory running in background ******"
    exit 0
fi

if [ $CPU_ONLY -eq 1 ]; then
    CPU_LOAD=1
    M_PSS=0
    M_DATA_STK=0
    M_CBS=0
fi

first=1
# for usleep
interval=$(($interval*1000))

while [ 1 ]
do
    ps_info=`ps $PS_OPT | grep -F "$program" | grep -v "grep" | grep -v "$MY_NAME"`
    pids=`echo "$ps_info" | awk '{print $1}'`
    if [ -z "$pids" ]; then
        echo "Couldn't find program '$program', maybe it's not running or exterminated!"
        exit 1
    fi

    if [ $CPU_LOAD -eq 1 ]; then
        top_info=`top -n1`
    fi

    if [ $PRINT_ALL -eq 1 ]; then
        if [ $CPU_ONLY -eq 0 ]; then
            cat /proc/meminfo
            echo
            echo "$ps_info"
            echo
        fi

        if [ $CPU_LOAD -eq 1 ]; then
            echo "$top_info"
            echo
        fi
    fi

    date_time=`date +%F-%H:%M:%S`
    console_log=""
    csv_title="Time, "
    csv_data="$date_time, "
    pss_total=0
    data_total=0
    stk_total=0
    cpu_total=0

    for pid in $pids
    do
# use eval to get dynamic variable name
#   eval rss_$pid=`cat /proc/$pid/status | grep "VmRSS" | awk '{print $2}'`
#   eval s=\${rss_$pid}
#   str=${str}"[PID=$pid $s] "

        #thread_name="$program"
        thread_name=""

        if [ $first -eq 1 ]; then
            if [ $M_PSS -eq 1 ]; then
                csv_title=${csv_title}"$thread_name(PID=$pid):PSS, "
            fi

            if [ $M_DATA_STK -eq 1 ]; then
                csv_title=${csv_title}"$thread_name(PID=$pid):VmData, $thread_name(PID=$pid):VmStk, "
            fi

            if [ $CPU_LOAD -eq 1 ]; then
                csv_title=${csv_title}"$thread_name(PID=$pid):CPU, "
            fi
        fi

        pss=`pmap -x $pid | tail -1 | awk '{print $3}'`
        pss_total=$(($pss_total+$pss))

        if [ $M_PSS -eq 1 ]; then
            csv_data=${csv_data}"$pss, "
            if [ $CONSOLE_PRINT -eq 1 ]; then
                console_log=${console_log}"[$thread_name(PID=$pid):PSS $pss] "
            fi
        fi

        if [ $M_DATA_STK -eq 1 ]; then
            if [ ! -d /proc/$pid ]; then
                echo "folder /proc/$pid doesn't exit!"
                data=0
                stk=0
            else
                status=`cat /proc/$pid/status`
                if [ $PRINT_ALL -eq 1 ]; then
                    echo "$status"
                    echo
                fi
                data=`echo "$status" | awk '{if($1=="VmData:") {print $2; exit 0}}'`
                stk=`echo "$status" | awk '{if($1=="VmStk:") {print $2; exit 0}}'`
            fi

            csv_data=${csv_data}"$data, $stk, "

            if [ $CONSOLE_PRINT -eq 1 ]; then
                if [ $M_PSS -eq 1 ]; then
                    console_log=${console_log}"[VmData: $data VmStk: $stk] "
                else
                    console_log=${console_log}"[$thread_name(PID=$pid)VmData: $data VmStk: $stk] "
                fi
            fi

            if [ $GET_TOTAL -eq 1 ]; then
                data_total=$(($data_total+$data))
                stk_total=$(($stk_total+$stk))
            fi
        fi

        if [ $CPU_LOAD -eq 1 ]; then
            #CPU usage, awk: get shell variable at the end
            cpu_usage=`echo "$top_info" | awk '{if ($1==pid) {print $7; exit 0}}' pid="$pid"`
            cpu_usage=${cpu_usage%%\%}

            csv_data=${csv_data}"$cpu_usage, "
            if [ $CONSOLE_PRINT -eq 1 ]; then
                console_log=${console_log}"[$thread_name(PID=$pid):CPU $cpu_usage%] "
            fi

            if [ $GET_TOTAL -eq 1 ]; then
                cpu_total=$(($cpu_total+$cpu_usage))
            fi
        fi
    done

    # print csv file title
    if [ $first -eq 1 ]; then
        if [ $M_DATA_STK -eq 1 ] && [ $GET_TOTAL -eq 1 ]; then
            csv_title=${csv_title}"VmDataTotal, VmStkTotal, "
        fi

        if [ $CPU_LOAD -eq 1 ] && [ $GET_TOTAL -eq 1 ]; then
            csv_title=${csv_title}"CPUTotal, CPUIdle, "
        fi

        if [ $CPU_ONLY -eq 0 ]; then
            csv_title=${csv_title}"MemUsed, "
        fi

        if [ $M_CBS -eq 1 ]; then
            csv_title=${csv_title}"Free, Cached, Buffers, Shmem, "
        fi

        echo "$csv_title" > $OUT_FILE
    fi

    # print each monitoring data
    if [ $M_DATA_STK -eq 1 ] && [ $GET_TOTAL -eq 1 ]; then
        csv_data=${csv_data}"$data_total, $stk_total, "
        if [ $CONSOLE_PRINT -eq 1 ]; then
            console_log=${console_log}"[VmDataTotal $data_total VmStkTotal $stk_total] "
        fi
    fi

    if [ $CPU_LOAD -eq 1 ] && [ $GET_TOTAL -eq 1 ]; then
        cpu_idle=`echo "$top_info" | awk '{if(NR==2) {print $8; exit 0}}'`
        cpu_idle=${cpu_idle%%\%}
        csv_data=${csv_data}"$cpu_total, $cpu_idle, "
        if [ $CONSOLE_PRINT -eq 1 ]; then
            console_log=${console_log}"[CPUTotal $cpu_total%] [CPUIdle $cpu_idle%] "
        fi
    fi

    if [ $CPU_ONLY -eq 0 ]; then
        csv_data=${csv_data}"$pss_total, "
        if [ $CONSOLE_PRINT -eq 1 ]; then
            console_log=${console_log}"[MemUsed $pss_total] "
        fi
    fi

    if [ $M_CBS -eq 1 ]; then
        mem_info=`cat /proc/meminfo`
        free_mem=`echo "$mem_info" | awk '{if($1=="MemFree:") {print $2; exit 0}}'`
        cache_mem=`echo "$mem_info" | awk '{if($1=="Cached:") {print $2; exit 0}}'`
        buffer_mem=`echo "$mem_info" | awk '{if($1=="Buffers:") {print $2; exit 0}}'`
        shmem=`echo "$mem_info" | awk '{if($1=="Shmem:") {print $2; exit 0}}'`

        csv_data=${csv_data}"$free_mem, $cache_mem, $buffer_mem, $shmem"
        if [ $CONSOLE_PRINT -eq 1 ]; then
            console_log=${console_log}"[Free $free_mem] [Cached $cache_mem] [Buffers $buffer_mem] [Shmem $shmem]"
        fi
    fi

    if [ $CONSOLE_PRINT -eq 1 ]; then
        echo "===Cr_Mem_Monitor===[$date_time] $console_log"
    fi

    echo "$csv_data" >> $OUT_FILE
    sync

    first=0
    usleep $interval
done

# command line to extract a comma seperated file which can be opened by MS Excel
# So that a graphic chart can be generated by Excel, eg:
# grep "===Cr_Mem_Monitor===" log.file | awk 'BEGIN{}{print $4, $6, $8}END{}' | sed 's/]//g' > monitor.csv
