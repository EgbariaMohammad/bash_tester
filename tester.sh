#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

show_help() {
    echo "Usage: $0 -e <executable> -i <input_dir> -eo <expected_output_dir>"
    echo "Options:"
    echo "  -h                Show this help message"
    echo "Arguments:"
    echo "  -e <executable>   The executable to run the tests on"
    echo "  -i <input_dir>    The directory containing the test input files"
    echo "  -eo <expected_output_dir> The directory containing the expected output files"
}

run_pretest() {
    if [ -f ${1%.*}_pre.sh ]
    then
        echo -n "Running pretest: "
        ./${1%.*}_pre.sh
        if [ $? -eq 0 ]
        then
            printf "${GREEN}done${NC}\n"
        else
            printf "${RED}error${NC}\n"
            exit 1
        fi
    fi
}

run_posttest() {
    if [ -f ${1%.*}_post.sh ]
    then
        echo -n "Running posttest: "
        ./${1%.*}_post.sh
        if [ $? -eq 0 ]
        then
            printf "${GREEN}done${NC}\n"
        else
            printf "${RED}error${NC}\n"
            exit 1
        fi
    fi
}

check_memory_leaks() {
    local log_file=$1
    local success_msg=$2
    local fail_msg=$3
    local check_str=$4

    if grep -q "$check_str" "$log_file"; then
        printf "Leak: ${GREEN}pass${NC}\n"
    else
        printf "Leak: ${RED}fail${NC}\n"
        cat "$log_file"
        RET=1
    fi
    rm "$log_file"
}

while getopts ":he:i:eo:" opt; do
    case ${opt} in
        h )
            show_help
            exit 0
            ;;
        e )
            executable=$OPTARG
            ;;
        i )
            input_dir=$OPTARG
            ;;
        eo )
            expected_output_dir=$OPTARG
            ;;
        \? )
            echo "Error: Invalid option '-$OPTARG'" 1>&2
            show_help
            exit 1
            ;;
        : )
            echo "Error: Option '-$OPTARG' requires an argument" 1>&2
            show_help
            exit 1
            ;;
    esac
done
shift $((OPTIND -1))

# Check if required arguments are provided
if [ -z "${executable}" ] || [ -z "${input_dir}" ] || [ -z "${expected_output_dir}" ]; then
    echo "Error: Missing required arguments"
    show_help
    exit 1
fi

# Ensure all files in input_dir have .in extension and corresponding .expected files in expected_output_dir
for file in "${input_dir}"/*; do
    if [[ ! "${file}" == *.in ]]; then
        echo "Error: All files in ${input_dir} must have a .in extension"
        exit 1
    fi
    expected_file="${expected_output_dir}/$(basename "${file}").expected"
    if [[ ! -f "${expected_file}" ]]; then
        echo "Error: Missing corresponding expected output file for ${file}"
        exit 1
    fi
done

# Check if running on macOS
IS_MAC=0
if [[ "$(uname)" == "Darwin" ]]; then
    IS_MAC=1
fi

shopt -s nullglob
RET=0

for i in ${input_dir}/*.in
do
    printf "test $i >>>  "

    # Run pretest script if it exists
    run_pretest $i

    # Execute the main executable with the input file and create an output file
    ./${executable} < $i > ${i%.*}e.out

    # Compare the output file with the expected output file
    diff ${i%.*}e.out ${expected_output_dir}/${i##*/}.expected
    if [ $? -ne 0 ]; then
        printf "${RED}Diff failed${NC}\n"
        RET=1
    else
        printf "Diff: ${GREEN}pass${NC}\n"
    fi

    rm ${i%.*}e.out

    
    if [ $IS_MAC -eq 0 ]; then
        # Perform memory leak check using valgrind if not on macOS
        valgrind --leak-check=full ./${executable} < $i &> ${i%.*}.valgrind_log
        check_memory_leaks "${i%.*}.valgrind_log" "Leak: ${GREEN}pass${NC}" "Leak: ${RED}fail${NC}" "ERROR SUMMARY: 0"
    else
        # Perform memory leak check on macOS
        leaks_result=$(0MallocStackLogging=1 leaks -quiet -atExist -- ./${executable} < $i > ${i%.*}v.out 1>/dev/null 2>/dev/null)
        check_memory_leaks "${i%.*}.leaks_log" "Leak: ${GREEN}pass${NC}" "Leak: ${RED}fail${NC}" "0 leaks for 0 total leaked bytes"
    fi

    # Run posttest script if it exists
    run_posttest $i
done

exit $RET
