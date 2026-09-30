#!/bin/bash
# Simulates two agents sending scan results to the Lunarscope master node.
# Usage: bash test_agents.sh
# Requires: curl, master node running on localhost:8080

BASE="http://localhost:8080/api/scan-result"

send() {
  curl -s -X POST "$BASE" \
    -H "Content-Type: application/json" \
    -d "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['status'])"
}

echo "Sending simulated scan results from 2 agents..."
echo ""

echo "--- Agent 001 (server-amsterdam) ---"
send '{"agent_id":"agent-001","hostname":"server-amsterdam","scan_type":"ssh_scan","severity":"critical","finding":"PermitRootLogin is not set to no (current: yes)"}'
send '{"agent_id":"agent-001","hostname":"server-amsterdam","scan_type":"ssh_scan","severity":"high","finding":"MaxAuthTries = 6 (expected: 4 or less)"}'
send '{"agent_id":"agent-001","hostname":"server-amsterdam","scan_type":"package_scan","severity":"critical","finding":"openssl 3.0.2 — CVE-2022-0778 (CVSS 7.5): Infinite loop in BN_mod_sqrt()"}'
send '{"agent_id":"agent-001","hostname":"server-amsterdam","scan_type":"package_scan","severity":"high","finding":"curl 7.81.0 — CVE-2022-22576 (CVSS 8.8): OAUTH2 bearer bypass"}'
send '{"agent_id":"agent-001","hostname":"server-amsterdam","scan_type":"services_scan","severity":"high","finding":"Telnet service (inetutils-telnet) is installed — transmits credentials in plaintext"}'
send '{"agent_id":"agent-001","hostname":"server-amsterdam","scan_type":"services_scan","severity":"medium","finding":"rsync service enabled at boot — unencrypted by default"}'
send '{"agent_id":"agent-001","hostname":"server-amsterdam","scan_type":"firewall_scan","severity":"pass","finding":"UFW is installed, enabled and default deny incoming"}'
send '{"agent_id":"agent-001","hostname":"server-amsterdam","scan_type":"account_scan","severity":"pass","finding":"Root is the only UID 0 account"}'

echo ""
echo "--- Agent 002 (server-eindhoven) ---"
send '{"agent_id":"agent-002","hostname":"server-eindhoven","scan_type":"ssh_scan","severity":"pass","finding":"PermitRootLogin = no"}'
send '{"agent_id":"agent-002","hostname":"server-eindhoven","scan_type":"ssh_scan","severity":"pass","finding":"MaxAuthTries = 3"}'
send '{"agent_id":"agent-002","hostname":"server-eindhoven","scan_type":"ssh_scan","severity":"pass","finding":"PermitEmptyPasswords = no"}'
send '{"agent_id":"agent-002","hostname":"server-eindhoven","scan_type":"package_scan","severity":"medium","finding":"nginx 1.18.0 — CVE-2021-23017 (CVSS 5.9): Off-by-one in DNS resolver"}'
send '{"agent_id":"agent-002","hostname":"server-eindhoven","scan_type":"package_scan","severity":"pass","finding":"All other packages up to date, no known CVEs"}'
send '{"agent_id":"agent-002","hostname":"server-eindhoven","scan_type":"account_scan","severity":"pass","finding":"No accounts with empty password fields in /etc/shadow"}'
send '{"agent_id":"agent-002","hostname":"server-eindhoven","scan_type":"firewall_scan","severity":"pass","finding":"UFW is installed, enabled and default deny incoming"}'

echo ""
echo "Done. Open http://localhost:8080 to see the dashboard."
