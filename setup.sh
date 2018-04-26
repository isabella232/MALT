#!/bin/bash

# start a KVM
triton instance create -w --name=$1 -N Joyent-SDC-Public,Joyent-SDC-Private,$2 -m hostname="$1"  ubuntu-certified-16.04 k4-highcpu-kvm-7.75G --script provision.sh
echo ""
echo -ne "Waiting for host to come up "
while [[ $(ssh -o StrictHostKeyChecking=no ubuntu@$(triton ip $1 2>/dev/null) 'ls -la' 2>/dev/null | wc -l) -lt 5 ]]; do
    echo -ne "."
    sleep 5
done
echo ""
ssh -t -o StrictHostKeyChecking=no ubuntu@$(triton ip $1) 'tail -n +0 -f /home/ubuntu/setup.log | { sed "/Setup completed/ q" && kill $$ ;}' 2>/dev/null
echo ""
echo "Grafana --> http://$(triton ip $1):3000/"
