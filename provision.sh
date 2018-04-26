#!/bin/bash

startTask() {
    which docker
    if [ $? -eq 0 ]; then
        return
    fi
    # install docker
    echo "Installing and setting up docker ..." >> /home/ubuntu/setup.log
    sudo curl https://raw.githubusercontent.com/joyent/triton-kubernetes/master/scripts/docker/17.03.sh | sh

    service docker stop
    DOCKER_SERVICE=$(systemctl status docker.service --no-pager | grep Loaded | sed 's~\(.*\)loaded (\(.*\)docker.service\(.*\)$~\2docker.service~g')
    sed 's~ExecStart=/usr/bin/dockerd -H\(.*\)~ExecStart=/usr/bin/dockerd --graph="/mnt/docker" -H\1~g' $DOCKER_SERVICE > /home/ubuntu/docker.conf && mv /home/ubuntu/docker.conf $DOCKER_SERVICE
    mkdir /mnt/docker
    bash -c "mv /var/lib/docker/* /mnt/docker/"
    rm -rf /var/lib/docker
    bash -c 'echo "{
  \"storage-driver\": \"overlay2\"
}" > /etc/docker/daemon.json'
    systemctl daemon-reload
    systemctl restart docker
    usermod -aG docker ubuntu

    # install influxdb
    # docker run --restart=always --name=influxdb -d -p 8086:8086 -p 8083:8083 -e INFLUXDB_ADMIN_ENABLED=true -e INFLUXDB_HTTP_ENABLED=true influxdb
    echo "Installing and setting up influxdb as a service ..." >> /home/ubuntu/setup.log
    apt-get update -y && apt-get upgrade -y
    wget https://dl.influxdata.com/influxdb/releases/influxdb_1.2.4_amd64.deb
    dpkg -i influxdb_1.2.4_amd64.deb

    echo '[meta]
  dir = "/var/lib/influxdb/meta"
[data]
  dir = "/var/lib/influxdb/data"
  wal-dir = "/var/lib/influxdb/wal"
[coordinator]
[retention]
[shard-precreation]
[monitor]
  store-enabled = true
  store-database = "_internal"
  store-interval = "10s"
[admin]
  enabled = true
  bind-address = ":8083"
[http]
  enabled = true
  bind-address = ":8086"
[subscriber]
[[graphite]]
[[collectd]]
[[opentsdb]]
[[udp]]
[continuous_queries]' > /home/ubuntu/influxdb.conf
    mv /home/ubuntu/influxdb.conf /etc/influxdb/influxdb.conf
    systemctl restart influxd.service

    # start grafana
    echo "Starting grafana as a container ..." >> /home/ubuntu/setup.log
    docker run --restart=always --name grafana -d -i -p 3000:3000 grafana/grafana

    # start telegraf agent (host_metrics)
    echo "Starting telegraf agent as a container ..." >> /home/ubuntu/setup.log
    curl -s https://gist.githubusercontent.com/fayazg/685f53b851854fe0381af29359185551/raw/75e115ce85aad6653fec7b20f87f966f1f2c9590/host_metrics.conf > /home/ubuntu/host_metrics.conf
    MY_IP=$(ip route get 8.8.8.8 | awk '{print $NF; exit}')
    sed "s/localhost/$MY_IP/g" /home/ubuntu/host_metrics.conf > /home/ubuntu/tmp.conf && mv /home/ubuntu/tmp.conf /home/ubuntu/host_metrics.conf
    docker run --restart=always --name telegraf -d -v /home/ubuntu/host_metrics.conf:/etc/telegraf/telegraf.conf:ro -v /var/run/docker.sock:/var/run/docker.sock telegraf

    ############################################################################
    echo "Waiting for grafana to come up." >> /home/ubuntu/setup.log
    while [[ $(curl --connect-timeout 5 --max-time 5 -s http://${MY_IP}:3000/ | grep -i "found" | wc -l) -eq 0 ]]; do
        echo -ne "." >> /home/ubuntu/setup.log
        sleep 5
    done
    echo "" >> setup.

    # create telegraf database
    curl -i -XPOST http://${MY_IP}:8086/query --data-urlencode "q=CREATE DATABASE telegraf" > /dev/null 2>&1
    echo "telegraf database created" >> /home/ubuntu/setup.log
    sleep 5

    # add influxdb as a datasource to the grafana instance
    echo "Adding influxdb as a datasource to grafana ..." >> /home/ubuntu/setup.log
    curl -s -H "Content-Type: application/json" -XPOST http://admin:admin@${MY_IP}:3000/api/datasources -d "{
    \"name\": \"influx\",
    \"type\": \"influxdb\",
    \"access\": \"proxy\",
    \"url\": \"http://${MY_IP}:8086\",
    \"database\": \"telegraf\"}" > /dev/null 2>&1

    # import default dashboards (host_metrics and containers_on_host)
    curl -s https://gist.githubusercontent.com/fayazg/73be7b5b5d632c10c18a93b7d92ac7df/raw/1ace6eea3c7975da753474a7a088f3cc883b1e46/host_metrics.json | sed "s~\${DS_INFLUXDB}~influx~g" | sed "s~dashboard-title~Host Metrics~g" > /home/ubuntu/host_metrics.json
    curl -X POST -H 'Accept: application/json' -H 'Content-Type: application/json' -d @/home/ubuntu/host_metrics.json "http://admin:admin@${MY_IP}:3000/api/dashboards/db" > /dev/null 2>&1
    echo "Imported host_metrics dashboard ..." >> /home/ubuntu/setup.log

    curl -s https://gist.githubusercontent.com/fayazg/2df8dd8a2dcea3f8f5db4e0ec25a4ffc/raw/13edd8f85953f90862d46fa156c7bd6e2fbdb6ab/containers_on_host.json | sed "s~\${DS_INFLUXDB}~influx~g" | sed "s~dashboard-title~Containers on Host~g" > /home/ubuntu/containers_on_host.json
    curl -X POST -H 'Accept: application/json' -H 'Content-Type: application/json' -d @/home/ubuntu/containers_on_host.json "http://admin:admin@${MY_IP}:3000/api/dashboards/db" > /dev/null 2>&1
    echo "Imported containers_on_host dashboard ..." >> /home/ubuntu/setup.log
    echo "" >> /home/ubuntu/setup.log
    echo "Setup completed." >> /home/ubuntu/setup.log
}

startTask
