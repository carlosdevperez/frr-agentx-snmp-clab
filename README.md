# FRR AgentX/SNMP two-node Containerlab topology

This is a self-contained lab for testing FRR SNMP exposure through Net-SNMP AgentX.

The lab builds one local Docker image and starts two FRR routers with Containerlab.

## Topology

```text
r1 eth1 10.0.12.1/30  ----  10.0.12.2/30 eth1 r2

r1:
  AS 65001
  router-id 1.1.1.1
  management IPv4 172.20.20.11
  SNMP exposed on host UDP/1161

r2:
  AS 65002
  router-id 2.2.2.2
  management IPv4 172.20.20.12
  SNMP exposed on host UDP/1162

snmp-exporter:
  management IPv4 172.20.20.20
  Prometheus SNMP exporter exposed on host TCP/9116

prometheus:
  management IPv4 172.20.20.21
  Prometheus exposed on host TCP/9090
```

Inside each container:

```text
snmpd
  └── AgentX socket /var/agentx/master
        ├── zebra -M snmp
        └── bgpd  -M snmp
```

## Files

```text
Dockerfile
start.sh
snmpd.conf
frr-agentx-bgp.clab.yml
monitoring/snmp.yml
monitoring/prometheus.yml
monitoring/alert.rules.yml
configs/r1/frr.conf
configs/r1/daemons
configs/r2/frr.conf
configs/r2/daemons
```

## Build the image

Run this from this directory:

```bash
docker build -t frr-snmp-agentx:latest .
```

## Deploy the topology

```bash
sudo clab deploy -t frr-agentx-bgp.clab.yml
```

## Verify the nodes

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
```

Expected containers:

```text
clab-frr-agentx-bgp-r1
clab-frr-agentx-bgp-r2
clab-frr-agentx-bgp-snmp-exporter
clab-frr-agentx-bgp-prometheus
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

## Walk the BGP4-MIB

r1:

```bash
snmpwalk -v2c -c public -On udp:127.0.0.1:1161 1.3.6.1.2.1.15
```

r2:

```bash
snmpwalk -v2c -c public -On udp:127.0.0.1:1162 1.3.6.1.2.1.15
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
curl -s 'http://127.0.0.1:9116/snmp?auth=public_v2&module=bgp4&target=172.20.20.11' | grep '^bgpPeerState'
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
```

Both routers should export one `bgpPeerState` series, and an established peer has value `6`.

## Verify the BGP-down alert

Break the r1-r2 link:

```bash
docker exec clab-frr-agentx-bgp-r1 ip link set eth1 down
```

After the BGP hold timer and the alert `for: 15s` period elapse, check the alert:

```bash
curl -sG 'http://127.0.0.1:9090/api/v1/query' --data-urlencode 'query=ALERTS{alertname="FrrBgpPeerDown",alertstate="firing"}'
```

Restore the link:

```bash
docker exec clab-frr-agentx-bgp-r1 ip link set eth1 up
```

## Destroy the lab

```bash
sudo clab destroy -t frr-agentx-bgp.clab.yml --cleanup
```

## Notes

This is a lab-only setup. It uses SNMPv2c with community `public` and wide-open access. For production, use SNMPv3 and restrict access with firewalling, management VRF, ACLs, or equivalent controls.
