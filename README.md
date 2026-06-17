# FRR AgentX/SNMP routed host Containerlab topology

This is a self-contained lab for testing FRR SNMP exposure through Net-SNMP AgentX, Prometheus alerting, and routed host-to-host traffic.

The lab builds local Docker images and starts two FRR routers, two attached Linux hosts, a lab-internal SNMP client, Prometheus `snmp_exporter`, a host-local blackbox exporter, and Prometheus with Containerlab.

## Topology

```text
h1 192.168.1.10/24 -- 192.168.1.1/24 r1
r1 eth1 10.0.12.1/30  ----  10.0.12.2/30 eth1 r2
r2 192.168.2.1/24 -- 192.168.2.10/24 h2

r1:
  AS 65001
  router-id 1.1.1.1
  advertises 192.168.1.0/24
  management address assigned dynamically by Containerlab
  reachable inside the lab as r1
  SNMP exposed inside the lab on UDP/161

r2:
  AS 65002
  router-id 2.2.2.2
  advertises 192.168.2.0/24
  management address assigned dynamically by Containerlab
  reachable inside the lab as r2
  SNMP exposed inside the lab on UDP/161

h1:
  data IPv4 192.168.1.10/24
  route to 192.168.2.0/24 via r1
  blackbox_exporter exposed inside the lab on TCP/9115

h2:
  data IPv4 192.168.2.10/24
  route to 192.168.1.0/24 via r2
  Python HTTP server exposed on TCP/8000

snmp-exporter:
  management address assigned dynamically by Containerlab
  reachable inside the lab as snmp-exporter
  Prometheus SNMP exporter exposed inside the lab on TCP/9116

prometheus:
  management address assigned dynamically by Containerlab
  reachable inside the lab as prometheus
  Prometheus exposed on host TCP/9090

snmp-client:
  management address assigned dynamically by Containerlab
  reachable inside the lab as snmp-client
  lab-internal toolbox for snmpwalk, curl, jq, ping, and tcpdump
```

Inside each router container:

```text
snmpd
  ├── UDP/161 on IPv4 and IPv6 management addresses
  └── AgentX socket /var/agentx/master
        ├── zebra -M snmp
        └── bgpd  -M snmp
```

## Files

```text
images/frr-snmp/Dockerfile
images/frr-snmp/start.sh
images/frr-snmp/snmpd.conf
images/snmp-client/Dockerfile
images/host/Dockerfile
Taskfile.yml
frr-agentx-bgp.clab.yml
monitoring/blackbox.yml
monitoring/snmp.yml
monitoring/prometheus.yml
monitoring/alert.rules.yml
configs/r1/frr.conf
configs/r1/daemons
configs/r2/frr.conf
configs/r2/daemons
```

## Build the images

Run this from this directory:

```bash
docker build -f images/frr-snmp/Dockerfile -t frr-snmp-agentx:latest .
docker build -f images/snmp-client/Dockerfile -t frr-snmp-client:latest .
docker build -f images/host/Dockerfile -t frr-host:latest .
```

Or with Task:

```bash
task build
```

## Deploy the topology

```bash
clab deploy -t frr-agentx-bgp.clab.yml
```

Or with Task:

```bash
task deploy
```

## Verify the nodes

```bash
clab inspect -t frr-agentx-bgp.clab.yml
clab inspect interfaces -t frr-agentx-bgp.clab.yml
```

Expected containers:

```text
clab-frr-agentx-bgp-r1
clab-frr-agentx-bgp-r2
clab-frr-agentx-bgp-h1
clab-frr-agentx-bgp-h2
clab-frr-agentx-bgp-snmp-exporter
clab-frr-agentx-bgp-prometheus
clab-frr-agentx-bgp-snmp-client
```

Or with Task:

```bash
task inspect
task inspect:interfaces
```

## Verify FRR daemons loaded the SNMP module

```bash
docker exec -it clab-frr-agentx-bgp-r1 bash -lc 'ps aux | egrep "snmpd|zebra|bgpd"'
docker exec -it clab-frr-agentx-bgp-r2 bash -lc 'ps aux | egrep "snmpd|zebra|bgpd"'
```

You should see:

```text
/usr/lib/frr/zebra ... -M snmp
/usr/lib/frr/bgpd  ... -M snmp
```

## Verify AgentX in FRR running config

```bash
docker exec -it clab-frr-agentx-bgp-r1 bash -lc 'vtysh -c "show running-config" | grep -i agentx'
docker exec -it clab-frr-agentx-bgp-r2 bash -lc 'vtysh -c "show running-config" | grep -i agentx'
```

Expected:

```text
agentx
```

## Verify BGP

```bash
docker exec -it clab-frr-agentx-bgp-r1 vtysh -c "show bgp summary"
docker exec -it clab-frr-agentx-bgp-r2 vtysh -c "show bgp summary"
```

The eBGP session should eventually become Established.

## Verify host traffic

From h1, test ICMP and HTTP reachability to h2 over the routed BGP path:

```bash
docker exec -it clab-frr-agentx-bgp-h1 ping -c 3 192.168.2.10
docker exec -it clab-frr-agentx-bgp-h1 curl -fsS http://192.168.2.10:8000 >/dev/null
```

Or with Task:

```bash
task traffic
```

## Walk the BGP4-MIB

r1:

```bash
docker exec -it clab-frr-agentx-bgp-snmp-client \
  snmpwalk -v2c -c public -On udp:r1:161 1.3.6.1.2.1.15
```

r2:

```bash
docker exec -it clab-frr-agentx-bgp-snmp-client \
  snmpwalk -v2c -c public -On udp:r2:161 1.3.6.1.2.1.15
```

Useful values to look for:

```text
1.3.6.1.2.1.15.2.0       local AS
1.3.6.1.2.1.15.4.0       BGP identifier / router ID
1.3.6.1.2.1.15.3.1.2.*   BGP peer state
1.3.6.1.2.1.15.3.1.9.*   remote AS
```

BGP peer state values in BGP4-MIB are commonly:

```text
1 idle
2 connect
3 active
4 opensent
5 openconfirm
6 established
```

## Verify Prometheus SNMP exporter

The SNMP exporter is configured with a small `bgp4` module in `monitoring/snmp.yml`.

Query r1 directly through the exporter:

```bash
docker exec -it clab-frr-agentx-bgp-snmp-client \
  curl -s 'http://snmp-exporter:9116/snmp?auth=public_v2&module=bgp4&target=r1' | grep '^bgpPeerState'
```

Expected when BGP is established:

```text
bgpPeerState{bgpPeerRemoteAddr="10.0.12.2"} 6
```

## Verify Prometheus

Open Prometheus at:

```text
http://127.0.0.1:9090
```

Or query the API:

```bash
curl -sG 'http://127.0.0.1:9090/api/v1/query' --data-urlencode 'query=bgpPeerState'
curl -sG 'http://127.0.0.1:9090/api/v1/query' --data-urlencode 'query=probe_success{job="host_reachability"}'
```

Both routers should export one `bgpPeerState` series, and an established peer has value `6`. The host reachability probe should return `probe_success` value `1`.

To run the config, BGP, SNMP, traffic, exporter, and Prometheus checks together:

```bash
task verify
```

## Verify the alerts

Break the r1-r2 link:

```bash
docker exec clab-frr-agentx-bgp-r1 ip link set eth1 down
```

After the BGP hold timer and the alert `for: 15s` period elapse, check firing alerts:

```bash
curl -sG 'http://127.0.0.1:9090/api/v1/query' --data-urlencode 'query=ALERTS{alertstate="firing"}'
```

Expected alerts include `FrrBgpPeerDown` for the routing control plane and `HostPathDown` for the h1-to-h2 application path.

Restore the link:

```bash
docker exec clab-frr-agentx-bgp-r1 ip link set eth1 up
```

Or with Task:

```bash
task break-link
task alerts
task restore-link
```

## Destroy the lab

```bash
clab destroy -t frr-agentx-bgp.clab.yml --cleanup
```

Or with Task:

```bash
task destroy
```

## Notes

This is a lab-only setup. It uses SNMPv2c with community `public` and wide-open access inside the lab network. For production, use SNMPv3 and restrict access with firewalling, management VRF, ACLs, or equivalent controls.

Containerlab/Docker DNS can return IPv6 addresses before IPv4 addresses. The router containers therefore bind `snmpd` on both IPv4 and IPv6 UDP/161, allowing Prometheus `snmp_exporter` to scrape stable node names such as `r1` and `r2` without static management IPv4 assignments.
