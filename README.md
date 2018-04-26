## Automated steps

Automated steps for monitoring.

### Monitoring server (Telegraf/Influx/Grafana)

```bash
# start a monitoring server (hostname=monitor)
./monitor.sh <monitoring host>
```

## Manual steps to monitoring

Manual steps to monitoring using TICK stack.

### InfluxDB and Grafana (containers) in a dedicated KVM

```bash
# start a KVM
triton instance create --name=monitor -N Joyent-SDC-Public,Joyent-SDC-Private -m user-data="hostname=monitor"  ubuntu-certified-16.04 k4-highcpu-kvm-7.75G

# install docker
curl https://releases.rancher.com/install-docker/1.12.sh | sh

# start influxdb
docker run --restart=always --name=influxdb -d -p 8086:8086 -p 8083:8083 -e INFLUXDB_ADMIN_ENABLED=true influxdb

# create a database in influxdb called telegraf
#   install influxdb client and run the following command in the client `influxdb`
create DATABASE telegraf

# start grafana
docker run --restart=always --name grafana -d -i -p 3000:3000 grafana/grafana

# add influxdb as a datasource to the grafana instance
curl -s -H "Content-Type: application/json" -XPOST http://admin:admin@<monitoring KVM>:3000/api/datasources -d '{
"name": "influx",
"type": "influxdb",
"access": "proxy",
"url": "http://<monitoring KVM>:8086",
"database": "telegraf"}'

# start telegraf agent with host_metrics.conf
cd telegraf
docker run --restart=always --name telegraf -d -v $PWD/host_metrics.conf:/etc/telegraf/telegraf.conf:ro -v /var/run/docker.sock:/var/run/docker.sock telegraf
```

### Telegraf Installation:
Each host will need to have telegraf agent running, pointing to influxdb as backend.

https://portal.influxdata.com/downloads[Install] telegraf using the system packages or start it in a `docker` container providing a `telegraf.config` file.

#### Running `telegraf` using `docker` container

```bash
docker run -d -v $PWD/telegraf.conf:/etc/telegraf/telegraf.conf:ro -v /var/run/docker.sock:/var/run/docker.sock telegraf
```

#### Running `telegraf` as a system service

Install using steps provided in [Install](https://portal.influxdata.com/downloads).
Modify `/etc/telegraf/telegraf.conf` by adding [plugins](#plugins) and influxdb details, and restart the service.
Start the telegraf monitor using the provided config file.

```bash
vi /etc/telegraf/telegraf.conf
systemctl restart telegraf
```

### Plugins
Multiple plugins can be enabled on a single agent:

#### Standard host collections

```properties
# Read metrics about cpu usage
[[inputs.cpu]]
  ## Whether to report per-cpu stats or not
  percpu = true
  ## Whether to report total system cpu stats or not
  totalcpu = true
  ## If true, collect raw CPU time metrics.
  collect_cpu_time = false

# Read metrics about disk usage by mount point
[[inputs.disk]]
  ## By default, telegraf gather stats for all mountpoints.
  ## Setting mountpoints will restrict the stats to the specified mountpoints.
  # mount_points = ["/"]

  ## Ignore some mountpoints by filesystem type. For example (dev)tmpfs (usually
  ## present on /run, /var/run, /dev/shm or /dev).
  ignore_fs = ["tmpfs", "devtmpfs", "devfs"]

# Read metrics about disk IO by device
[[inputs.diskio]]
  ## By default, telegraf will gather stats for all devices including
  ## disk partitions.
  ## Setting devices will restrict the stats to the specified devices.
  # devices = ["sda", "sdb"]
  ## Uncomment the following line if you need disk serial numbers.
  # skip_serial_number = false
  #
  ## On systems which support it, device metadata can be added in the form of
  ## tags.
  ## Currently only Linux is supported via udev properties. You can view
  ## available properties for a device by running:
  ## 'udevadm info -q property -n /dev/sda'
  # device_tags = ["ID_FS_TYPE", "ID_FS_USAGE"]
  #
  ## Using the same metadata source as device_tags, you can also customize the
  ## name of the device via templates.
  ## The 'name_templates' parameter is a list of templates to try and apply to
  ## the device. The template may contain variables in the form of '$PROPERTY' or
  ## '${PROPERTY}'. The first template which does not contain any variables not
  ## present for the device is used as the device name tag.
  ## The typical use case is for LVM volumes, to get the VG/LV name instead of
  ## the near-meaningless DM-0 name.
  # name_templates = ["$ID_FS_LABEL","$DM_VG_NAME/$DM_LV_NAME"]

# Get kernel statistics from /proc/stat
[[inputs.kernel]]

# Read metrics about memory usage
[[inputs.mem]]

# Get the number of processes and group them by status
[[inputs.processes]]

# Read metrics about swap memory usage
[[inputs.swap]]

# Read metrics about system load & uptime
[[inputs.system]]
```

#### docker containers

```properties
# Read metrics about docker containers
[[inputs.docker]]
  ## Docker Endpoint
  ##   To use TCP, set endpoint = "tcp://[ip]:[port]"
  ##   To use environment variables (ie, docker-machine), set endpoint = "ENV"
  endpoint = "unix:///var/run/docker.sock"
  ## Only collect metrics for these containers, collect all if empty
  container_names = []
  ## Timeout for docker list, info, and stats commands
  timeout = "5s"

  ## Whether to report for each container per-device blkio (8:0, 8:1...) and
  ## network (eth0, eth1, ...) stats or not
  perdevice = true
  ## Whether to report for each container total blkio and network stats or not
  total = true
```

For monitoring the docker containers on a host, make sure to add the `telegraf` user to `docker` group:

```bash
usermod -a -G docker telegraf
```

#### http/https connections

```properties
# HTTP/HTTPS request given an address a method and a timeout
[[inputs.http_response]]
  ## Server address (default http://localhost)
  address = "http://github.com"
  ## Set response_timeout (default 5 seconds)
  response_timeout = "5s"
  ## HTTP Request Method
  method = "GET"
  ## Whether to follow redirects from the server (defaults to false)
  follow_redirects = true
  ## HTTP Request Headers (all values must be strings)
  # [inputs.http_response.headers]
  #   Host = "github.com"
  ## Optional HTTP Request Body
  # body = '''
  # {'fake':'data'}
  # '''

  ## Optional substring or regex match in body of the response
  ## response_string_match = "\"service_status\": \"up\""
  ## response_string_match = "ok"
  ## response_string_match = "\".*_status\".?:.?\"up\""

  ## Optional SSL Config
  # ssl_ca = "/etc/telegraf/ca.pem"
  # ssl_cert = "/etc/telegraf/cert.pem"
  # ssl_key = "/etc/telegraf/key.pem"
  ## Use SSL but skip chain & host verification
  # insecure_skip_verify = false
```

#### [GrafanaLab's Kubernetes](https://grafana.com/plugins/raintank-kubernetes-app) Plugin

This plugin requires a [*graphite*](https://hub.docker.com/r/sitespeedio/graphite/) instance as datasource.

```bash
# start a graphite container to store the data gathered by this new plugin (username/password are both guest by default)
docker run -d --name graphite -p 8080:80 -p 2003:2003 sitespeedio/graphite
```

Add the *graphite* instance as datasource in *grafana*.

| Argument | Value |
| :------------ | :----------- |
| Name | graphite |
| Type | Graphite |
| Url | http://\<monitoring KVM>:8080/ |
| Access | proxy |
| Basic Auth | X |
| User | guest |
| Password | guest |

Using the `~/.kube/config` file configuration, populate the Kubernetes Plugin settings in grafana.

```properties
apiVersion: v1
kind: Config
clusters:
- cluster:
    api-version: v1
    insecure-skip-tls-verify: true
    server: "https://165.225.173.67:8080/r/projects/1a7/kubernetes"
  name: "monitoring"
contexts:
- context:
    cluster: "monitoring"
    user: "monitoring"
  name: "monitoring"
current-context: "monitoring"
users:
- name: "monitoring"
  user:
    username: "039635F83EC48F93B843"
    password: "XzM1N3LEPpPrpSxDcqQaW6poMZH2qLo7Kbkoyq9q"
```
<sub>Example `~/.kube/config` file</sub>


| Argument | Value |
| :------------ | :----------- |
| Name | monitoring |
| Url | https://165.225.173.67:8080/r/projects/1a7/kubernetes |
| Access | proxy |
| Basic Auth | X |
| With Credentials | X |
| User | 039635F83EC48F93B843 |
| Password | XzM1N3LEPpPrpSxDcqQaW6poMZH2qLo7Kbkoyq9q |
| Datasource | graphite |
| Carbon Host | \<monitoring KVM> |
| Port | 2003 |

<sub>Kubernetes Plugin Settings in Grafana</sub>

```bash

# get in the monitoring KVM
triton ssh monitoring

# get in the grafana container
docker exec -ti grafana bash

# install command on the grafana container
grafana-cli plugins install raintank-kubernetes-app

# leave the container
exit

# restart the grafana container to enable the new plugin
docker restart grafana
```

### Monitoring:

#### Autopilot Pattern Applications (wordpress)
Autopilot Pattern Applications come with a prometheus instance that has all the application health. For these apps, we just have to run the `monitoring-apa.sh` passing it the monitoring host and url of the prometheus instance. This will add the prometheus instance as a datasource to Grafana with a dashboard.

Example 1: Monitoring [`autopilotpattern/wordpress`](https://github.com/autopilotpattern/wordpress)

```bash
# get and start wordpress example
git clone https://github.com/autopilotpattern/wordpress.git
cd wordpress
docker-compose up -d
docker-compose scale consul=3 memcached=3 mysql=3 nfs=3 nginx=2 wordpress=3
# consul is at :8500
# nginx/wordpress at :80
# prometheus at :9090
```

Now that autopilotpattern/wordpress is running, we can run the monitor script against it.

```bash
./monitor-apa.sh <monitoring-host> <prometheus-url>
# monitoring-host is name of the triton host that includes Grafana
# prometheus-url is the full url (e.g. http://3.4.1.5:9090) of prometheus that is part of autopilotpattern/wordpress
```

This will add prometheus as a datasource to Grafana with a dashboard.