#!/bin/bash
ulimit -n 65535
ulimit -c unlimited
echo 0 > /proc/sys/kernel/randomize_va_space
if ps aux | grep "./ShareMemory" | grep -v grep >/dev/null 2>&1; then
    echo "ShareMemory is running"
else
    cd /home/tlbb/Server/
    ./shm clear >/dev/null 2>&1
    rm -rf exit.cmd quitserver.cmd
    ./shm start >/dev/null 2>&1
    sleep 10
    cd /home/tlbb/Server/
    ./World >/dev/null 2>&1 &
    sleep 5
    cd /home/tlbb/Server/
    unset LD_PRELOAD
    unset ASAN_OPTIONS
    export LD_LIBRARY_PATH=/home/tlbb/Server:$LD_LIBRARY_PATH
    setarch x86_64 -R env LD_PRELOAD="/home/tlbb/Server/Serverhook.so" ./Server_fix >/dev/null 2>&1 &
    sleep 30
    ./Login >/dev/null 2>&1 &
    sleep 1
    cd /home/billing/
    ./billing up -d >/dev/null 2>&1 &
    sleep 5
    exit
fi
cd /home/billing && ./billing up -d
