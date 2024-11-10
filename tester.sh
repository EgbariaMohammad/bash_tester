#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

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

if [ $# -ne 4 ]
then
    echo "Usage: $0 <run file> <tests_dir> <expected_output_dir>"
    exit 1
fi

shopt -s nullglob
RET=0

for i in $2/*.in
do
    printf "test $i >>>  "
    run_pretest $i
    if [ "${i##*.}" = "in" ]
    then
        ./$1 -e $i ${i%.*}e.out
        diff ${i%.*}e.out ${3}/${i##*/}.expected
        rm ${i%.*}e.out
    else
        ./$i -e $(realpath $1) ${i%.*}.out
    fi
    if [ $? -eq 0 ]
    then
        printf "Encoded Working: ${GREEN}pass${NC},   "
    else
        printf "Encoded Working: ${RED}fail${NC},   "
        RET=1
    fi
    if [ "${i##*.}" = "in" ]
    then
        ./$1 -i $i ${i%.*}.out
        diff ${i%.*}.out ${3}/${i##*/}.expected
        rm ${i%.*}.out
    else
        ./$i -i $(realpath $1) ${i%.*}.out
    fi
    if [ $? -eq 0 ]
    then
        printf "Inverted Working: ${GREEN}pass${NC},   "
    else
        printf "Inverted Working: ${RED}fail${NC},   "
        RET=1
    fi
    if [ "${i##*.}" = "in" ]
    then
        valgrind --log-file=$i.valgrind_log --leak-check=full ./$1 -i $i ${i%.*}v.out 1>/dev/null 2>/dev/null
        rm ${i%.*}v.out
    else
        ./$i "valgrind --log-file=$(pwd)/$i.valgrind_log --leak-check=full $(realpath $1)" 1>/dev/null 2>/dev/null
    fi
    if [ -f $i.valgrind_log ]
    then
        cat $i.valgrind_log | grep "ERROR SUMMARY: 0" > /dev/null
        if [ $? -eq 0 ]
        then
            printf "Leak: ${GREEN}pass${NC}\n"
        else
            printf "Leak: ${RED}fail${NC}\n"
            cat $i.valgrind_log
            RET=1
        fi
    else
        printf "Leak: ${RED}couldn't get valgrind file${NC}\n"
        RET=1
    fi
    rm $i.valgrind_log
    run_posttest $i
done

exit $RET
