#!/bin/bash

set -E

# Commands not found don't cause an ERR, so trap any exit from the script
trap got_error ERR
trap got_exit EXIT

# Global variables
STATE=
TIMEOUT=
STARTING_TEMP=
OLD_FAN_SPEED=

function clean_exit()
{
    if [ -w $FAN_SPEED_DEVICE ]; then
        set_fan 255
    fi
    cleanup
    exit 1
}

function got_error() {
    trap - EXIT
    trap - ERR
    echo "FAILURE: Command had an error"
    clean_exit
}

function got_exit() {
    trap - EXIT
    trap - ERR
    echo "Exiting.  Setting fan to high speed"
    clean_exit
}

# Cleanup
function clean_device_file()
{
    local DEVICE_FILE=$1
    if [[ -f "$DEVICE_FILE" && "$DEVICE_FILE" =~ ^/tmp ]]; then
        rm "$DEVICE_FILE"
    fi
}

function cleanup()
{
    clean_device_file "$FAN_SPEED_DEVICE"
    clean_device_file "$TEST_CPU_TEMP_DEVICE"
    clean_device_file "$CPU_TEMP_DEVICE_CORE1"
    clean_device_file "$CPU_TEMP_DEVICE_CORE2"
    clean_device_file "$CPU_TEMP_DEVICE_CORE3"
    clean_device_file "$CPU_TEMP_DEVICE_CORE4"
}

#--------------------SUPPORT--------------------
function _parse_uptime()
{
    local UPTIME_STRING=$1
    local LOAD_FLOAT
    local LOAD_INT

    LOAD_FLOAT=$( echo "$UPTIME_STRING" | awk -F'load average:' '{print $2}' | sed -e 's/,.*$//' )
    LOAD_INT=$(awk "BEGIN {print int($LOAD_FLOAT*100)}")
    echo "$LOAD_INT"
}

function _get_now()
{
    date +'%s'
}

#--------------------SIGNALS--------------------
function timedout()
{
    local NOW
    NOW=$(_get_now)

    if [ $(( NOW - TIMEOUT )) -ge 0 ]; then
        return 0
    else
        return 1
    fi
}

function overtemp()
{
    if [ "$(get_cpu_temp)" -gt "$CPU_TEMP_MAX" ]; then
        return 0
    else
        return 1
    fi
}

#--------------------GETTERS AND SETTERS--------------------
function get_cpu_load()
{
    _parse_uptime "$(uptime)"
}

function get_cpu_temp()
{
    # Pick the highest core temp
    max=0
    read CORE1_TEMP < $CPU_TEMP_DEVICE_CORE1
    read CORE2_TEMP < $CPU_TEMP_DEVICE_CORE2
    read CORE3_TEMP < $CPU_TEMP_DEVICE_CORE3
    read CORE4_TEMP < $CPU_TEMP_DEVICE_CORE4

    for var in $CORE1_TEMP $CORE2_TEMP $CORE3_TEMP $CORE4_TEMP
    do
        if [ "$var" -gt "$max" ]; then
            max="$var"
        fi
    done
    echo "$((max/1000))"
}

function get_fan()
{
    cat $FAN_SPEED_DEVICE
}

function set_fan()
{
    local NEW_FAN_SPEED=$1
    # Hide failures for tests to work.  Scope issue, fan_device is set to actual h/w during test when exit trap fires
    echo "$NEW_FAN_SPEED" > "$FAN_SPEED_DEVICE" 2> /dev/null
}

function set_timeout()
{
    local DESIRED_DELAY=$1
    local FUTURE_TIME
    local NOW
    NOW=$(_get_now)
    FUTURE_TIME=$((DESIRED_DELAY + NOW))
    TIMEOUT=$FUTURE_TIME
}


#--------------------SAFETY FUNCTIONS--------------------

# So that every state doesn't have to have a branch to cooling,
# this function is run in the main loop to jump to cooling.
function state_override()
{
    if overtemp; then
        if  [[ ! "$STATE" = "cooling_wait" ]]; then
            STATE="cooling"
        fi
    fi
}

# If we get too hot, just peg the fan
function failsafe()
{
    if [ "$(get_cpu_temp)" -ge 60 ]; then
        set_fan 255
    fi
}

#--------------------STATE MACHINE CODE--------------------
function cooling()
{
    local CURRENT_FAN_SPEED
    local NEW_FAN_SPEED
    local CURRENT_TEMP
    local TEMP_DIFF

    if ! overtemp; then
        set_timeout $HOLDING_TIMEOUT_AFTER_COOLING
        STATE=holding
        return
    fi

    CURRENT_TEMP=$(get_cpu_temp)

    TEMP_DIFF=$(( CURRENT_TEMP - CPU_TEMP_MAX ))

    if [ "$TEMP_DIFF" -lt 0 ]; then
        TEMP_DIFF=0
    fi

    # Temp's above max, increase fan speed

    CURRENT_FAN_SPEED=$(get_fan)

    NEW_FAN_SPEED=$((CURRENT_FAN_SPEED + TEMP_DIFF*5 ))

    if [ "$NEW_FAN_SPEED" -gt 255 ]; then
        NEW_FAN_SPEED=255
    fi

    set_fan $NEW_FAN_SPEED

    set_timeout $COOLING_TIMEOUT_WHILE_COOLING

    STATE="cooling_wait"
}

function cooling_wait()
{
    if timedout; then
        STATE="cooling"
    else
        STATE="cooling_wait"
    fi
}

function holding()
{
    # If the CPU is under load, don't go searching for a lower fan speed
    if ( ! timedout || [ "$(get_cpu_load)" -ge $CPU_LOAD_THRESHOLD ]) ; then
        STATE="holding"
    else
        STATE="searching"
        STARTING_TEMP=$(get_cpu_temp)
    fi
}

function searching()
{
    local FAN_SPEED_DECREASE
    local CURRENT_FAN_SPEED
    local NEW_FAN_SPEED

    CURRENT_FAN_SPEED=$(get_fan)

    FAN_SPEED_DECREASE=$(( (CURRENT_FAN_SPEED - FAN_SPEED_MIN)/2 + 1))

    NEW_FAN_SPEED=$((CURRENT_FAN_SPEED - FAN_SPEED_DECREASE))

    if [ "$NEW_FAN_SPEED" -lt "$FAN_SPEED_MIN" ]; then
        NEW_FAN_SPEED="$FAN_SPEED_MIN"
    fi

    OLD_FAN_SPEED=$CURRENT_FAN_SPEED
    set_fan $NEW_FAN_SPEED

    set_timeout $SEARCHING_TIMEOUT_WHILE_SEARCHING

    STATE="searching_wait"
}

function searching_wait()
{
    local TEMP_DIFF
    local CURRENT_TEMP

    if timedout; then
        CURRENT_TEMP=$(get_cpu_temp)
        TEMP_MARGIN=$(( CURRENT_TEMP - STARTING_TEMP - ALLOWED_TEMP_INCREASE ))
        if [ $TEMP_MARGIN -ge 0 ]; then
            # Increase the fan speed back to where it was one search step ago
            set_fan "$OLD_FAN_SPEED"
            set_timeout "$HOLDING_TIMEOUT_AFTER_SEARCHING"
            STATE="holding"
            return
        fi
        STATE="searching"
    fi
}

#--------------------TEST CODE--------------------
(
    set -e

    #--------------------TEST SUPPORT--------------------

)


