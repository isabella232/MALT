#!/bin/bash


MY_IP=$(ip route get 8.8.8.8 | awk '{print $NF; exit}')

#Point telegraf to collect the cassandra and jvm metrics to the ip of the jolokia agent

sed -i "s~\$(MYIP)~${MY_IP}~g" ./telegraf/telegraf_jolokia.conf

docker-compose up -d

echo "Waiting for grafana to come up."
while [[ $(curl --connect-timeout 5 --max-time 5 -s http://${MY_IP}:3000/ | grep -i "found" | wc -l) -eq 0 ]]; do
       echo -ne "."
       sleep 5
done
echo ""

echo "Grafana: http://${MY_IP}:3000 - admin/admin"

open-grafana "http://${MY_IP}:3000"

open-grafana() {
  browser_command=echo
  if which open &>/dev/null && ! ls -l $(which open) | grep openvt &> /dev/null; then
            # "open" exists and isn't a symlink to openvt
            browser_command=open
  fi

  $browser_command "$1"
}
