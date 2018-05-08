# cr_cpu_profile.sh
# a tiny tool to profile the cpu loading of a process and its child threads
# profiling data will be saved into a formatted csv file

#/proc/loadavg is a average running process number in 1, 5., 15 minutes
# it can't not be used as a cpu usage percentage.
# refer to http://www.samirchen.com/linux-cpu-performance/

#TODO:

#usage example
# cr_cpu_profile.sh -T chromium

# uncomment for debugging
#set -xv

# the version of this script
VER=0.2
echo "`basename $0` version $VER"
echo

GET_BY_TOP=0
MY_NAME=$0
DEFAULT_INTERVAL=5000
DEFAULT_PROGRAM="chromium"
THREAD_MODE=0
CONSOLE_PRINT=0
GET_TOTAL=0
interval=$DEFAULT_INTERVAL
program=$DEFAULT_PROGRAM
PID_MODE=0
TID_MODE=0
p_ids=""
t_ids=""
HAS_GETOPTS=0
OUT_FILE="./cr_cpu_loading"

#detect if target shell has getopts, some embeded system use busybox, may hasn't getopts
getopts > /dev/null 2&>1
if [ $? -eq 0 ]; then
    HAS_GETOPTS=1
fi

usage()
{
    echo -e "\nUsage : `basename $0` [-tpnTh] [-o out_file] [-i interval] [-P pid1|pid2] [-S tid1|tid2] [program]"
    echo "Note :"
    echo "    program         The process name need to be monitered, if not specified, then monitor default program $program"
    echo "    -t              profile each thread memory and cpu usage"
    echo "    -n              get cpu usage by top command instead of calculate from /proc/[pid]/stat"
    echo "    -p              print monitoring info in console"
    echo "    -P pid1|pid2    profile the specified pid processes"
    echo "    -S tid1|tid2    profile the specified threads"
    echo "    -T              print total of all process with same program name"
    echo "    -i interval     The interval time (in millisecond) of checking, if no interval specified, use default $DEFAULT_INTERVAL milliseconds"
    echo "    -o out_file     The output file pathname, default is $OUT_FILE in current work directory"
    echo "    -h              get help"
    echo ""
}

if [ $HAS_GETOPTS -eq 1 ]; then
    while getopts ntpTo:i:P:S: OPTION
    do
        case $OPTION in
            i) interval=$OPTARG
                ;;
            o) OUT_FILE=$OPTARG
                ;;
            P) PID_MODE=1
                p_ids=$OPTARG
                ;;
            S) TID_MODE=1
                t_ids=$OPTARG
                ;;
            t) THREAD_MODE=1
                ;;
            T) GET_TOTAL=1
                ;;
            p) CONSOLE_PRINT=1
                ;;
            n) GET_BY_TOP=1
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
                    P)
                        if [ -n "${param:1}" ]; then
                            p_ids=${param:1}
                        else
                            p_ids=$2
                            shift
                        fi
                        PID_MODE=1
                        loop_end=1
                        ;;
                    S)
                        if [ -n "${param:1}" ]; then
                            t_ids=${param:1}
                        else
                            t_ids=$2
                            shift
                        fi
                        TID_MODE=1
                        loop_end=1
                        ;;
                    t) THREAD_MODE=1
                        ;;
                    T) GET_TOTAL=1
                        ;;
                    p) CONSOLE_PRINT=1
                        ;;
                    n) GET_BY_TOP=1
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
#echo THREAD_MODE $THREAD_MODE
#echo CONSOLE_PRINT $CONSOLE_PRINT
#echo GET_TOTAL $GET_TOTAL
#echo INTERVAL $interval
#echo PROGRAM $program
#echo HAS_GETOPTS $HAS_GETOPTS
#echo OUT_FILE $OUT_FILE
#exit 0

OUT_FILE=${OUT_FILE}_`date +%F-%H%M%S`.csv

if [ $PID_MODE -eq 1 ]; then
    pids=${p_ids//|/ }
else
    if [ $TID_MODE -eq 0 ]; then
        pids=`ps | grep -F "$program" | grep -v "grep" | grep -v "$MY_NAME" | awk '{print $1}'`
        if [ -z "$pids" ]; then
            echo "!!!!!! $program is not running !!!!!!"
            #    ps
            exit 1
        fi
    fi
fi

if [ $TID_MODE -eq 1 ]; then
    tids=${t_ids//|/ }
else
    tids=""
fi

# top command can't get cpu usage of a thread, if in thread mode, we must calculte cpu usage by stat files
if [ $THREAD_MODE -eq 1 ]; then
    GET_BY_TOP=0
fi

get_thread_cpu_usage ()
{
    local _pid=$1
    local _tid=$2
    # handle the thread name with SPACE character
    stat_info=`cat /proc/$_pid/task/$_tid/stat`
    #echo "$stat_info"
    thread_name=${stat_info%%\)*}
    thread_name=${thread_name##*\(}
    thread_name=${thread_name// /_}

    stat_info=${stat_info##*\)}
    if [ $first -eq 1 ]; then
        # amount of utime,stime
        eval thread_time_$cpid=`echo "$stat_info" | awk '{if(NR==1) {print ($12+$13); exit 0}}'`
        cpu_usage=0
        eval v=\${thread_time_$_tid}
        #echo "$thread_name:$_tid, v=$v"
    else
        cur_thread_time=`echo "$stat_info" | awk '{if(NR==1) {print ($12+$13); exit 0}}'`
        eval pre_value=\${thread_time_$_tid}
        #echo "$thread_name:$_tid, pre=$pre_value, cur=$cur_thread_time"
        if [ -z "$pre_value" ]; then
            cpu_usage=0
        else
            cpu_usage=$((($cur_thread_time-$pre_value)*100/$cpu_time_diff))
            eval thread_time_$_tid=\${cur_thread_time}
        fi
    fi
    #echo "$thread_name:$_tid, $cpu_usage"
    csv_data=${csv_data}"$thread_name(PID=$_tid):, $cpu_usage%, "
    if [ $GET_TOTAL -eq 1 ]; then
        cpu_total=$(($cpu_total+$cpu_usage))
    fi
}

processor_num=`cat /proc/cpuinfo | awk '{if($1=="processor") cpu_num=$3}END{print cpu_num}'`
processor_num=$(($processor_num+1))

first=1
interval=$(($interval*1000))

while [ 1 ]
do
    date_time=`date +%F-%H:%M:%S`
    csv_data="$date_time, "

    if [ $GET_TOTAL -eq 1 ]; then
        cpu_total=0
    fi

    if [ $GET_BY_TOP -eq 1 ]; then
        top_info=`top -n1`
    else
        if [ $first -eq 1 ]; then
            cpu_time_total=`awk '{if(NR==1) {print ($2+$3+$4+$5+$6+$7+$8+$9+$10+$11); exit 0}}' /proc/stat`
            cpu_idle_total=`awk '{if(NR==1) {print $5; exit 0}}' /proc/stat`
            cpu_io_wait=`awk '{if(NR==1) {print $6; exit 0}}' /proc/stat`
        else
            cur_cpu_time_total=`awk '{if(NR==1) {print ($2+$3+$4+$5+$6+$7+$8+$9+$10+$11); exit 0}}' /proc/stat`
            cur_cpu_idle_total=`awk '{if(NR==1) {print $5; exit 0}}' /proc/stat`
            cur_cpu_io_wait=`awk '{if(NR==1) {print $6; exit 0}}' /proc/stat`

            cpu_time_diff=$(($cur_cpu_time_total-$cpu_time_total))
            cpu_idle_diff=$(($cur_cpu_idle_total-$cpu_idle_total))
            cpu_io_wait_diff=$(($cur_cpu_io_wait-$cpu_io_wait))

            cpu_time_total=$cur_cpu_time_total
            cpu_idle_total=$cur_cpu_idle_total
            cpu_io_wait=$cur_cpu_io_wait
        fi
    fi

    for pid in $pids
    do
        if [ ! -d /proc/$pid ]; then
            echo "folder /proc/$pid doesn't exit! maybe it is not running"
            continue
        fi

        if [ $THREAD_MODE -eq 1 ] && [ -d /proc/$pid/task ]; then
            # get all chrild thread's stat
            for cpid in `ls /proc/$pid/task/`
            do
                if [ ! -f /proc/$pid/task/$cpid/stat ]; then
                    continue
                fi
                get_thread_cpu_usage $pid $cpid
            done
        else
            thread_name=`awk '{if(NR==1) {print $2; exit 0}}' /proc/$pid/stat`

            if [ $GET_BY_TOP -eq 1 ]; then
                # get cpu usage by top directly
                cpu_usage=`echo "$top_info" | awk '{if ($1==pid) {print $7; exit 0}}' pid="$pid"`
                cpu_usage=${cpu_usage%%\%}
            else
                # calculate cpu usage by /proc/stat and /proc/[pid]/stat
                #cat /proc/$pid/stat

                if [ $first -eq 1 ]; then
                    # amount of utime,stime,cutime,cstime
                    eval process_time_$pid=`awk '{if(NR==1) {print ($14+$15+$16+$17); exit 0}}' /proc/$pid/stat`
                    eval v=\${process_time_$pid}
                    #echo "pid=$pid, time=$v"
                    cpu_usage=0
                else
                    cur_process_time=`awk '{if(NR==1) {print ($14+$15+$16+$17); exit 0}}' /proc/$pid/stat`
                    eval pre_value=\${process_time_$pid}
                    #echo "pid=$pid, pre=$pre_value, cur=$cur_process_time"
                    cpu_usage=$((($cur_process_time-$pre_value)*100/$cpu_time_diff))
                    eval process_time_$pid=\${cur_process_time}
                fi
            fi

            #echo "pid=$pid, $cpu_usage"
            csv_data=${csv_data}"${thread_name}PID=$pid:, $cpu_usage%, "
            if [ $GET_TOTAL -eq 1 ]; then
                cpu_total=$(($cpu_total+$cpu_usage))
            fi
        fi
    done

    for tid in $tids
    do
        for folder in `ls -d /proc/*/`
        do
            if [ -d $folder/task/$tid ]; then
                ptid=`basename $folder`
                get_thread_cpu_usage $ptid $tid
                break
            fi
        done
    done

    if [ $GET_TOTAL -eq 1 ]; then
        if [ $GET_BY_TOP -eq 1 ]; then
            cpu_idle=`echo "$top_info" | awk '{if(NR==2) {print $8; exit 0}}'`
            cpu_idle=${cpu_idle%%\%}
            csv_data=${csv_data}"Total:, $cpu_total%, Idle:, $cpu_idle%, "
        else
            if [ $first -eq 1 ]; then
                cpu_idle=0
                io_wait=0
            else
                cpu_idle=$(($cpu_idle_diff * 100 / $cpu_time_diff))
                io_wait=$(($cpu_io_wait_diff * 100/ $cpu_time_diff))
            fi
            csv_data=${csv_data}"Total:, $cpu_total%, Idle:, $cpu_idle%, IO_Wait:, $io_wait%, "
        fi
    fi

    if [ $CONSOLE_PRINT -eq 1 ]; then
        echo "===Cr_CPU_Profile===, $csv_data"
    fi

    if [ $first -eq 1 ]; then
        echo "$csv_data" > $OUT_FILE
    else
        echo "$csv_data" >> $OUT_FILE
    fi

    sync

    first=0
    usleep $interval
done
