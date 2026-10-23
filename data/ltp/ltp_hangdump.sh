#!/bin/sh
# SPDX-License-Identifier: FSFAP
#
# Usage: ltp_hangdump.sh DELAY OUTFILE
#
# Sleep DELAY seconds, then dump kernel state useful for debugging a hung
# test into OUTFILE. run_ltp.pm starts this in the background before a test
# and kills it when the test finishes, so a dump is only written for tests
# still running after DELAY seconds. Set DELAY below LTP's own timeout so the
# state is captured before LTP's timeout handler kills the test processes.

delay=$1
out=$2

sleep "$delay" || exit 0

{
	echo "=== ltp_hangdump: test still running after ${delay}s, $(date) ==="
	echo "--- uname"
	uname -a
	echo "--- loadavg"
	cat /proc/loadavg
	echo "--- tasks in D state"
	ps -eLo pid,tid,ppid,stat,etimes,wchan:32,comm | awk 'NR == 1 || $4 ~ /D/'
	echo "--- kernel stacks of D state tasks"
	for t in /proc/[0-9]*/task/[0-9]*; do
		state=$(awk '{ print $3 }' "$t/stat" 2>/dev/null)
		[ "$state" = D ] || continue
		echo "-- $t ($(cat "$t/comm" 2>/dev/null))"
		cat "$t/stack" 2>/dev/null
	done
	mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug 2>/dev/null
	echo "--- sunrpc client tasks"
	for c in /sys/kernel/debug/sunrpc/rpc_clnt/*; do
		[ -r "$c/tasks" ] || continue
		echo "-- $c"
		cat "$c/info" "$c/tasks" 2>/dev/null
	done
	echo "--- sunrpc transports"
	for x in /sys/kernel/debug/sunrpc/rpc_xprt/*; do
		[ -r "$x/info" ] || continue
		echo "-- $x"
		cat "$x/info" 2>/dev/null
	done
	echo "--- nfsd"
	cat /proc/fs/nfsd/pool_stats /proc/fs/nfsd/threads 2>/dev/null
	ps -eo pid,stat,wchan:32,comm | awk 'NR == 1 || $4 == "nfsd"'
	echo "--- nfs mountstats"
	awk '/^device / { p = / fstype nfs/ } p' /proc/self/mountstats
	echo "--- nfsstat"
	nfsstat 2>&1
	echo "--- meminfo"
	cat /proc/meminfo
} >"$out" 2>&1

# Blocked task backtraces also go to the kernel log, i.e. the serial console.
echo w >/proc/sysrq-trigger
sleep 2
dmesg >>"$out" 2>&1
echo "=== ltp_hangdump: done ===" >>"$out"
