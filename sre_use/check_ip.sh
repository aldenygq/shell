#!/bin/bash
function check_ip_by_awk(){
    IP=$1
    VALID_CHECK=$(echo $IP|awk -F. '{if(NF==4 && $1>0 && $1<=255 && $2>=0 && $2<=255 && $3>=0 && $3<=255 && $4>0 && $4<255) {print "yes"}}')
    if echo $IP|grep -E "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$">/dev/null; then
        if [ "$VALID_CHECK" = "yes" ]; then
            echo "$IP available."
        else
            echo "$IP not available!"
        fi
    else
        echo "Format error!"
    fi
}
check_ip_by_awk $1


function check_ip_by_cut(){
    IP=$1
    if [[ $IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        FIELD1=$(echo $IP|cut -d. -f1)
        FIELD2=$(echo $IP|cut -d. -f2)
        FIELD3=$(echo $IP|cut -d. -f3)
        FIELD4=$(echo $IP|cut -d. -f4)
        if [ $FIELD1 -le 255 -a $FIELD2 -le 255 -a $FIELD3 -le 255 -a $FIELD4 -le 255 ]; then
            echo "$IP available."
        else
            echo "$IP not available!"
        fi
    else
        echo "Format error!"
    fi
}
check_ip_by_cut $1


function check_ip_by_cycle(){
    IP=$1
    VALID_CHECK=$(echo $IP|awk -F. '{if(NF==4 && $1>0 && $1<=255 && $2>=0 && $2<=255 && $3>=0 && $3<=255 && $4>0 && $4<255) {print "yes"}}')
    if echo $IP|grep -E "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$">/dev/null; then
        if [ "$VALID_CHECK" = "yes" ]; then
            echo "$IP available."
        else
            echo "$IP not available!"
        fi
    else
        echo "Format error!"
    fi
}
while true; do
    read -p "Please enter IP: " IP
    check_ip_by_cycle $IP
    [ $? -eq 0 ] && break || continue
done
