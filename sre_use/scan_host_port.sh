#!/bin/bash
HOST=$1
PORTS="22 25 80 3306 8080 26088 26089"
for PORT in $PORTS; do
    (nc -z -w5 $HOST $PORT) &> /dev/null
    if [ $? -eq 0 ]; then
        echo "$PORT is opening....."
    else
        echo "$PORT close"
    fi
done
