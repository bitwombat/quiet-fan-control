#!/bin/bash

# Global variables
STATE=

CPU_TEMP_MAX=50
TIMEOUT=
FAN_SPEED_MIN=70

# Timeout values for various states' waiting
HOLDING_TIMEOUT_AFTER_COOLING=30
HOLDING_TIMEOUT_AFTER_SEARCHING=600
COOLING_TIMEOUT_WHILE_COOLING=4
SEARCHING_TIMEOUT_WHILE_SEARCHING=5

# CPU load where we don't try to search lower fan speeds
# Since bash only does integers, this is 100x the value reported
# by uptime.  So 80 corresponds to a load of 0.8
CPU_LOAD_THRESHOLD=80

# During searching, how much can the temp go up by before we bail
ALLOWED_TEMP_INCREASE=3

# Change trap so bad command exit is considered an erro
trap got_error EXIT


#--------------------TEST SETUP--------------------

# Create file-based proxies for hardware devices
FAN_SPEED_DEVICE=/tmp/$$
CPU_TEMP_DEVICE_CORE1=/tmp/$$.core1
CPU_TEMP_DEVICE_CORE2=/tmp/$$.core2
CPU_TEMP_DEVICE_CORE3=/tmp/$$.core3
CPU_TEMP_DEVICE_CORE4=/tmp/$$.core4

# Test variables
TEST_CPU_LOAD=
TEST_NOW=

# Allow setting CPU temp, only here in test
function set_cpu_temp()
{
    local HW_TEMP
    local REQUESTED_TEMP=$1

    HW_TEMP=$((REQUESTED_TEMP * 1000))

    echo "$HW_TEMP" > "$CPU_TEMP_DEVICE_CORE1"
    echo "$HW_TEMP" > "$CPU_TEMP_DEVICE_CORE2"
    echo "$HW_TEMP" > "$CPU_TEMP_DEVICE_CORE3"
    echo "$HW_TEMP" > "$CPU_TEMP_DEVICE_CORE4"
}



#--------------------TESTS--------------------

echo "--------------------"

# Test of signals
echo "9000" > "$CPU_TEMP_DEVICE_CORE1"
echo "1000" > "$CPU_TEMP_DEVICE_CORE2"
echo "2000" > "$CPU_TEMP_DEVICE_CORE3"
echo "3000" > "$CPU_TEMP_DEVICE_CORE4"
assertEquals "max CPU core temp detected (test 1)" 9 "$(get_cpu_temp)"

echo "1000" > "$CPU_TEMP_DEVICE_CORE1"
echo "9000" > "$CPU_TEMP_DEVICE_CORE2"
echo "2000" > "$CPU_TEMP_DEVICE_CORE3"
echo "3000" > "$CPU_TEMP_DEVICE_CORE4"
assertEquals "max CPU core temp detected (test 2)" 9 "$(get_cpu_temp)"

echo "1000" > "$CPU_TEMP_DEVICE_CORE1"
echo "2000" > "$CPU_TEMP_DEVICE_CORE2"
echo "9000" > "$CPU_TEMP_DEVICE_CORE3"
echo "3000" > "$CPU_TEMP_DEVICE_CORE4"
assertEquals "max CPU core temp detected (test 3)" 9 "$(get_cpu_temp)"

echo "1000" > "$CPU_TEMP_DEVICE_CORE1"
echo "2000" > "$CPU_TEMP_DEVICE_CORE2"
echo "3000" > "$CPU_TEMP_DEVICE_CORE3"
echo "9000" > "$CPU_TEMP_DEVICE_CORE4"
assertEquals "max CPU core temp detected (test 4)" 9 "$(get_cpu_temp)"

set_cpu_temp 50
assertEquals "CPU temp read correctly" 50 "$(get_cpu_temp)"

set_cpu_temp 55
CPU_TEMP_MAX=54
assertTrue "Overtemp detected" "overtemp"

set_cpu_temp 55
CPU_TEMP_MAX=55
assertFalse "Overtemp not falsely detected" "overtemp"

assertNotEquals "_get_now works" "$(_get_now)" 0

assertEquals "cpu load works" 32 "$(_parse_uptime " 21:35:39 up 22:44, 12 users,    load average: 0.32, 0.34, 0.39")"

assertEquals "cpu load works" 344 "$(_parse_uptime " 21:35:39 up 22:44, 12 users,   load average: 3.44, 0.34, 0.39")"

assertEquals "cpu load works" 102 "$(_parse_uptime " 23:50:06 up 2 days, 58 min, 17 users,  load average: 1.02, 0.72, 0.46")"


# Tests of support functions

# Override support functions with test versions
function _get_now()
{
    echo "$TEST_NOW"
}

function get_cpu_load()
{
    echo "$TEST_CPU_LOAD"
}


TEST_NOW=9
set_timeout 1255
assertEquals "Set timeout works" 1264 "$TIMEOUT"

TIMEOUT=1234
TEST_NOW=1235
assertTrue "Timeout detected" "timedout"

TIMEOUT=1234
TEST_NOW=1233
assertFalse "Timeout doesn't fire early" "timedout"

set_fan 555
assertEquals "Function get_fan works" "$(cat "$FAN_SPEED_DEVICE")" "$(get_fan)"

set_fan 55
assertEquals "Function set_fan works" 55 "$(get_fan)"


# Tests of state

STATE="cooling"
set_cpu_temp 56
CPU_TEMP_MAX=55
$STATE
assertEquals "Cooling state transitions to cooling wait if overtemp" "cooling_wait" "$STATE"

STATE="cooling"
set_cpu_temp 56
CPU_TEMP_MAX=55
TIMEOUT=1
TEST_NOW=9
$STATE
assertEquals "Cooling state sets 4 second timeout transitioning to cooling wait" 13 $TIMEOUT

STATE="cooling"
set_cpu_temp 55
CPU_TEMP_MAX=55
TIMEOUT=1
TEST_NOW=9
$STATE
assertEquals "Cooling state sets 30 second timeout transitioning to holding" 39 $TIMEOUT

STATE="cooling_wait"
TIMEOUT=13
TEST_NOW=12
$STATE
assertEquals "Cooling_wait state holds if no timeout" "cooling_wait" "$STATE"

TIMEOUT=13
TEST_NOW=13
$STATE
assertEquals "Cooling_wait state transitions to cooling upon timeout" "cooling" "$STATE"

set_fan 60
STATE="cooling"
set_cpu_temp 56
CPU_TEMP_MAX=55
$STATE
assertEquals "Cooling state increases fan speed by temp difference times 5 if temp is above max (test 1)" 65 "$(get_fan)"

set_fan 60
STATE="cooling"
set_cpu_temp 57
CPU_TEMP_MAX=55
$STATE
assertEquals "Cooling state increases fan speed by temp difference times 5 if temp is above max (test 2)" 70 "$(get_fan)"

set_fan 60
STATE="cooling"
set_cpu_temp 55
CPU_TEMP_MAX=55
$STATE
assertEquals "Cooling state does not increase fan speed if temp at max" 60 "$(get_fan)"

set_fan 60
STATE="cooling"
set_cpu_temp 50
CPU_TEMP_MAX=55
$STATE
assertEquals "Cooling state does not increase fan speed if temp below max" 60 "$(get_fan)"

set_fan 255
STATE="cooling"
set_cpu_temp 56
CPU_TEMP_MAX=55
$STATE
assertEquals "Cooling state does not increase fan speed past 255" 255 "$(get_fan)"

STATE="cooling"
set_cpu_temp 55
CPU_TEMP_MAX=55
$STATE
assertEquals "Cooling state transitions to holding if temp at or below max" "holding" "$STATE"

STATE="holding"
TEST_CPU_LOAD=1
TIMEOUT=$(_get_now)
$STATE
assertEquals "Holding state transitions to searching at timeout" "searching" "$STATE"

STATE="holding"
TIMEOUT=$(_get_now)
TEST_CPU_LOAD=$CPU_LOAD_THRESHOLD
$STATE
assertEquals "Holding state doesn't try to search if CPU usage is high" "holding" "$STATE"

# Note: it's actually half plus one so that we make it to the minimum speed
STATE="searching"
set_fan 110
$STATE
assertEquals "Searching state lowers fan speed by 1/2 the distance to min fan speed (test 1)" 89 "$(get_fan)"

# Note: Dependent on above test
# Note: it's actually half plus one so that we make it to the minimum speed
STATE="searching"
$STATE
assertEquals "Searching state lowers fan speed by 1/2 the distance to min fan speed (test 2)" 79 "$(get_fan)"

# Note: Dependent on above test
STATE="searching"; $STATE
STATE="searching"; $STATE
STATE="searching"; $STATE
assertEquals "Searching state lowers fan speed to minimum but not below" "$FAN_SPEED_MIN" "$(get_fan)"

STATE="searching"
$STATE
assertEquals "Searching state transitions to searching_wait" "searching_wait" "$STATE"

STATE="searching"
TEST_NOW=9
TIMEOUT=1
$STATE
assertEquals "Searching state sets timeout of 5 on transition" 14 "$TIMEOUT"

STATE="searching_wait"
TIMEOUT=$(_get_now)
$STATE
assertEquals "Searching wait state transitions to searching on timeout" "searching" "$STATE"

STATE="searching"
set_cpu_temp 80
$STATE
TIMEOUT=$(_get_now)
CURRENT_CPU_TEMP=$(get_cpu_temp)
set_cpu_temp $(( CURRENT_CPU_TEMP  + ALLOWED_TEMP_INCREASE ))
$STATE
assertEquals "Searching wait state transitions to holding when temp goes up by margin" "holding" "$STATE"

STATE="searching"
set_cpu_temp 80
$STATE
TIMEOUT=$(_get_now)
CURRENT_CPU_TEMP=$(get_cpu_temp)
set_cpu_temp $(( CURRENT_CPU_TEMP + ALLOWED_TEMP_INCREASE ))
TEST_NOW=10
TIMEOUT=1
$STATE
assertEquals "Searching wait state sets proper timeout when it goes back to holding" 610 "$TIMEOUT"

# Since STARTING_TEMP is set at the beginning of the search cycle, it has to be set
# from the holding state as it transitions out to searching.
STATE="holding"
set_cpu_temp 80
TIMEOUT=$(_get_now)
TEST_CPU_LOAD=10
# Transition from holding to searching.  STARTING_TEMP should be set
$STATE
# Transition from searching to searching_wait
$STATE
# Now check searching wait's behaviour as the assert explains below
CURRENT_CPU_TEMP=$(get_cpu_temp)
set_cpu_temp $(( CURRENT_CPU_TEMP + ALLOWED_TEMP_INCREASE - 1))
TIMEOUT=$(_get_now)
$STATE
assertEquals "Searching wait state transitions to searching when temp goes up by less than margin" "searching" "$STATE"


# Override and failsafe tests
set_cpu_temp $((CPU_TEMP_MAX + 1))
STATE='holding'
state_override
assertEquals "State override function function goes to cooling state when over max temp" "cooling" "$STATE"

set_cpu_temp $CPU_TEMP_MAX
STATE="searching"
state_override
assertEquals "State override function does not go to cooling state when exactly max temp" "searching" "$STATE"

set_cpu_temp $((CPU_TEMP_MAX + 1))
STATE="cooling_wait"
state_override
assertEquals "State override function does not go to cooling state when cooling_wait" "cooling_wait" "$STATE"

set_cpu_temp 40
set_fan 200
failsafe
assertEquals "Failsafe does not peg fan speed if temp not high" 200 "$(get_fan)"

set_cpu_temp 60
set_fan 200
failsafe
assertEquals "Failsafe pegs fan speed if temp is high" 255 "$(get_fan)"

stats

# Done
# Made it to the end, turn off the exit trap
trap - EXIT

cleanup
