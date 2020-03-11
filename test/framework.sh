#!/bin/bash

    . colour_echos

    PASS_COUNT=0
    FAIL_COUNT=0

    function _pass()
    {
        echo -n -e "${GREEN}✓${NORMAL}"
        let PASS_COUNT+=1
    }

    function _fail()
    {
        red "FAIL: EXPECTED=$expected ACTUAL=$actual"
        let FAIL_COUNT+=1
    }

    function assertEquals()
    {
        msg=$1; shift
        expected=$1; shift
        actual=$1; shift
        printf "%4s " "${BASH_LINENO[$i]} "
        if [ "$expected" != "$actual" ]; then
            _fail
        else
            _pass
        fi
        echo " $msg"
    }

    function assertNotEquals()
    {
        msg=$1; shift
        expected=$1; shift
        actual=$1; shift
        printf "%4s " "${BASH_LINENO[$i]} "
        if [ "$expected" == "$actual" ]; then
            _fail
        else
            _pass
        fi
        echo " $msg"
    }

    function assertTrue()
    {
        msg=$1
        fn=$2
        printf "%4s " "${BASH_LINENO[$i]} "
        if ! $fn; then
            red "FAIL: function came back false"
        else
            _pass
        fi
        echo " $msg"
    }

    function assertFalse()
    {
        msg=$1
        fn=$2
        printf "%4s " "${BASH_LINENO[$i]} "
        if $fn; then
            red "FAIL: function came back true"
        else
            _pass
        fi
        echo " $msg"
    }

    function stats()
    {
        if [ $FAIL_COUNT = 0 ]; then
            green "*** All $PASS_COUNT tests passed"
        else
            red "*** $FAIL_COUNT of $((PASS_COUNT + FAIL_COUNT)) tests failed"
        fi
    }

