#!/bin/bash

#=========================================================
# Author         : Junjie Huang
# Email          : junjie.huang@seraphic-corp.com
# Last modified  : 2018-05-08 10:55
# Filename       : elf_dependencies_analyzer.sh
# Description    : a tool to analyze dependencies for elf
#=========================================================

ROOT_ELF=""
MAX_DEPTH=3
SYS_ROOT=$(pwd)
LD_LIB_PATH=""
CHECK_PRELINK=0
PRINT_PATH=0
IGNORE_SCANNED=0
DRAW_WITH_DOT=0
SAVE_IN_CSV=0

function usage() {
  echo -e "\nUsage : `basename $0` [OPTION...] [FILES]"
  echo "Note :"
  echo "    -c                                 Check if the elf file has been prelinked or not"
  echo "    -p                                 Print the path of elf; otherwise print name as default"
  echo "    -i                                 Ignore the elf file which has been scanned, to be unique"
  echo "    -g | --graph                       Draw the dependencies graphs with graphviz and dot"
  echo "    -t | --table                       Generate the depencies table in cvs format"
  echo "    -h | --help                        Get help"
  echo "    --depth=MAX_DEPTH                  The max depth to scan"
  echo "    --root=ROOT_PATH                   Prefix all paths with ROOT_PATH "
  echo "    --ld-library-path=LD_LIBRARY_PATH  What LD_LIBRARY_PATH should be used"
  echo ""
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

# parse the arguments
for i in "$@"; do
  case $i in
    -c)
      CHECK_PRELINK=1
      shift
      ;;
    -p)
      PRINT_PATH=1
      shift
      ;;
    -i)
      IGNORE_SCANNED=1
      shift
      ;;
    -g|--graph)
      DRAW_WITH_DOT=1
      shift
      ;;
    -t|--table)
      SAVE_IN_CSV=1
      shift
      ;;
    -d=*|--depth=*)
      MAX_DEPTH="${i#*=}"
      shift
      ;;
    -r=*|--root=*)
      SYS_ROOT="${i#*=}"
      shift
      ;;
    -l=*|--ld-library-path=*)
      LD_LIB_PATH="${i#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 1
      ;;
    *)
      ROOT_ELF=$i
      ;;
  esac
done

ROOT_ELF_PATH=${SYS_ROOT}${ROOT_ELF}
ROOT_ELF_NAME=$(basename ${ROOT_ELF_PATH})
LD_LIB_LIST=($(echo ${LD_LIB_PATH} | tr : ' '))


DOT_SOURCE_FILE=${ROOT_ELF_NAME}".dot"
DOT_OUTPUT_FILE=${ROOT_ELF_NAME}".png"
CSV_SOURCE_FILE=${ROOT_ELF_NAME}".csv"

BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)
RESET=$(tput sgr0)

last_child_mask=()
scanned_elf_list=()

function print_hierarchy_symbols() {
  if [[ $depth -gt 0 ]]; then
    local i=1
    while [[ $i -lt $depth ]]; do
      if [[ ${last_child_mask[$i]} -eq 0 ]]; then
        echo -n '│  '
      else
        echo -n '   '
      fi
      i=$((i+1))
    done

    if [[ ${last_child_mask[$depth]} -eq 0 ]]; then
      echo -n '├──'
    else
      echo -n '└──'
    fi
  fi
}

# PARAMETER 1: ELF file path
function print_file_path() {
  local path=$1
  local name=$(basename $path)

  if [[ SAVE_IN_CSV -eq 1 ]]; then
    save_in_cvs ${name}
  fi

  print_hierarchy_symbols

  if [[ ${CHECK_PRELINK} -eq 1 ]]; then
    if [[ $(readelf -S ${path} | grep -i "prelink") ]]; then
      if [[ ${PRINT_PATH} -eq 1 ]]; then
        echo "${GREEN}${path} [y]${RESET}"
      else
        echo "${GREEN}${name} [y]${RESET}"
      fi
    else
      if [[ ${PRINT_PATH} -eq 1 ]]; then
        echo "${RED}${path} [n]${RESET}"
      else
        echo "${RED}${name} [n]${RESET}"
      fi
    fi
  else
    if [[ ${PRINT_PATH} -eq 1 ]]; then
      echo "${MAGENTA}${path}${RESET}"
    else
      echo "${MAGENTA}${name}${RESET}"
    fi
  fi
}

function generate_dot_header() {
  if [[ -f ${DOT_SOURCE_FILE} ]]; then
    rm -rf ${DOT_SOURCE_FILE}
  fi

  cat << EOT >> ${DOT_SOURCE_FILE}
digraph "${ROOT_ELF_NAME}" {
  graph [
    rankdir=LR
    bgcolor=white
    fontsize=10
  ]
  edge [
    color=blue
  ]
  node [
    shape=record
    fontcolor=red
    color=black
    style=filled
    fillcolor=white
  ]
EOT
}

# PARAMETER 1: parent elf path
# PARAMETER 2: current elf path
function draw_in_dot() {
  local pre=$(basename $1)
  local cur=$(basename $2)
  echo "  \"$pre\" -> \"$cur\";" >> ${DOT_SOURCE_FILE}
}

function generate_dot_footer() {
  echo "}" >> ${DOT_SOURCE_FILE}
}

# PARAMETER 1: ELF file name
function save_in_cvs() {
  local elf=$1
  if [[ $depth -gt 0 ]]; then
    local i=1
    while [[ $i -le $depth ]]; do
      echo -n ', ' >> ${CSV_SOURCE_FILE}
      i=$((i+1))
    done
  fi
  echo $elf >> ${CSV_SOURCE_FILE}
}

# PARAMETER 1: ELF file path
function list_dependencies() {
  local elf_list=$(readelf -d $1 | grep NEEDED | \
    awk -F'[' '{print $2}' | awk -F']' '{print $1}')
  echo ${elf_list}
}

depth=0

# PARAMETER 1: ELF file path
function dependencies_scan() {
  local target=$1
  local dep_list=($(list_dependencies ${target})) #array

  if [[ ${IGNORE_SCANNED} -eq 1 ]]; then
    if [[ ${scanned_elf_list[@]} =~ (^|[[:space:]])"${target}"($|[[:space:]]) ]]; then
      return
    else
      scanned_elf_list+=(${target})
    fi
  fi

  for elf_name in "${dep_list[@]}"; do
    local file_list=()

    if [[ ${#LD_LIB_LIST[@]} -ne 0 ]]; then
      for lib in "${LD_LIB_LIST[@]}"; do
        lib=${SYS_ROOT}${lib}
        if [[ -d ${lib} ]]; then
          file_list=($(find ${lib} -name ${elf_name}))
          if [[ ${#file_list[@]} -ne 0 ]]; then
            break
          fi
        fi
      done
    else
      file_list=($(find . -name ${elf_name}))
    fi

    if [[ ${#file_list[@]} -eq 0 ]]; then
      #file_list=($(find . -name ${elf_name}))
      #echo "could not found ${elf_name}"
      continue
    fi

    ((depth++))

    if [[ ${dep_list[-1]} = ${elf_name} ]]; then
      last_child_mask[$depth]=1
    else
      last_child_mask[$depth]=0
    fi

    file_path=${file_list[0]}
    print_file_path ${file_path}
    if [[ ${DRAW_WITH_DOT} -eq 1 ]]; then
      draw_in_dot ${target} ${file_path}
    fi

    if [[ $depth -lt ${MAX_DEPTH} ]]; then
      dependencies_scan ${file_path}
    fi

    ((depth--))
  done
}

function main() {
  if [[ ${DRAW_WITH_DOT} -eq 1 ]]; then
    generate_dot_header
  fi

  if [[ ${SAVE_IN_CSV} -eq 1 ]]; then
    rm -rf ${CSV_SOURCE_FILE}
  fi

  print_file_path ${ROOT_ELF_PATH}
  dependencies_scan ${ROOT_ELF_PATH}

  if [[ ${DRAW_WITH_DOT} -eq 1 ]]; then
    generate_dot_footer
    if [[ $(which dot) ]]; then
      dot -Tpng -o ${DOT_OUTPUT_FILE} ${DOT_SOURCE_FILE}
    else
      echo "Could not find \"dot\" command, please install graphviz!"
    fi
  fi
}

main
