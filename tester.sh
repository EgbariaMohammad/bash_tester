#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

show_help() {
    echo "Usage: $0 -e <executable> -i <input_dir> -o <expected_output_dir>"
    echo "Options:"
    echo "  -h                Show this help message"
    echo "Arguments:"
    echo "  -e <executable>   The executable to run the tests on"
    echo "  -i <input_dir>    The directory containing the test input files"
    echo "  -o <expected_output_dir> The directory containing the expected output files"
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
    local check_str=$2

    if grep -q "$check_str" "$log_file"; then
        printf "Leak: ${GREEN}pass${NC}\n"
    else
        printf "Leak: ${RED}fail${NC}\n"
        # cat "$log_file"
        RET=1
    fi
}

while getopts ":he:i:o:" opt; do
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
        o )
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
    basefile=$(basename "${file}" .in)
    expected_file="${expected_output_dir}/${basefile}.expected"
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
    printf "test $i >>>  \n"

    # Run pretest script if it exists
    run_pretest $i
    
    base_filename=$(basename "$i" .in)
    # Execute the main executable with the input file and create an output file
    ./${executable} < $i > ${base_filename}.out
    # Compare the output file with the expected output file
    diff ${base_filename}.out ${expected_output_dir}/${base_filename}.expected
    if [ $? -ne 0 ]; then
        printf "${RED}Diff failed${NC}\n"
        RET=1
    else
        printf "Diff: ${GREEN}pass${NC}\n"
    fi

    rm ${base_filename}.out

    
    if [ $IS_MAC -eq 0 ]; then
        # Perform memory leak check using valgrind if not on macOS
        valgrind_command="valgrind --leak-check=full ./${executable} < $i &> ${base_filename}.valgrind_log"
        eval $valgrind_command > /dev/null 2>&1
        check_memory_leaks "${base_filename}.valgrind_log" "ERROR SUMMARY: 0"
        rm "${base_filename}.valgrind_log"
    else
        # Perform memory leak check on macOS
        leaks_command="MallocStackLogging=1 leaks -quiet --atExit -- ./${executable} < $i &> ${base_filename}.leaks_log"
        # Execute the command and redirect both stdout and stderr to /dev/null to suppress all output
        eval $leaks_command > /dev/null 2>&1
        check_memory_leaks "${base_filename}.leaks_log" "0 leaks for 0 total leaked bytes"
        rm "${base_filename}.leaks_log"
    fi

    # Run posttest script if it exists
    run_posttest $i
done

exit $RET
