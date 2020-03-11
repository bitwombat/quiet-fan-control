quiet-fan controls a CPU fan using a state machine that ensures the lowest fan
speed, while keeping your CPU below a desired temperature.

## Background
Other fan control algorithms (e.g. PID, linear), cause the fan speed to vary
frequently, which is acoustically annoying. Often they will also allow the CPU
temperature to oscillate (which causes thermal stress). This happens even when
hysteresis is incorporated.

For example, when the CPU is at the desired temperature, a PID algorithm will
have an error term of 0, meaning no fan speed adjustments will be made. But it
could be the result of the ambient air temperature. That means you're
experiencing more fan noise than is necessary to keep the CPU cool.

## Quiet-fan's algorithm
Quiet-fan uses a state machine to occasionally test lower fan speeds to see if
the CPU temperature is negatively affected. This ensures quiet-fan will "hunt"
for the lowest possible fan RPM that still keeps your CPU below a threshold.

If your system load is high, it will not test lower RPMs, further reducing fan
RPM and CPU temperature oscillations.

![state diagram](https://github.com/bitwombat/quiet-fan-control/blob/master/doc/states.png)

## Installation/usage
There's probably a proper systemd way of doing this, but this line in
`/etc/rc.local` works:

    /root/sbin/fan_adj > /var/log/fan_adj.log &

Saving stdout to a log file is unnecessary.

## Configuration
This is a system utility, thus its configuration isn't friendly or error-proof. Edit the program variables in `quiet-fan` in the DEVICES and CONFIGURATION SETTINGS sections.

settings in
## Bugs
System load is not the same as CPU load, so if the disks are busy, the fan RPMs
may be kept high unnecessarily.

