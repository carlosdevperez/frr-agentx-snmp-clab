#!/usr/bin/env bash
set -euo pipefail

mkdir -p /run/frr /var/log/frr /var/agentx
chown -R frr:frr /run/frr /var/log/frr || true
chown -R Debian-snmp:Debian-snmp /var/agentx || true

# Start the master SNMP agent. It listens on UDP/161 and accepts AgentX subagents.
snmpd -f -Lo -C -c /etc/snmp/snmpd.conf &
SNMPD_PID="$!"

# Start FRR daemons using /etc/frr/daemons.
# The per-node daemons files load zebra/bgpd with "-M snmp".
/usr/lib/frr/frrinit.sh start

_term() {
    /usr/lib/frr/frrinit.sh stop || true
    kill "${SNMPD_PID}" 2>/dev/null || true
    wait "${SNMPD_PID}" 2>/dev/null || true
}
trap _term TERM INT

# Keep the container alive while preserving signal handling.
wait "${SNMPD_PID}"
