#!/usr/bin/env bash

set -euo pipefail

DATA_DEVICE=/dev/xvdb
NEO4J_HTTP_PORT=7474
NEO4J_DATA_DIR=/mnt
NEO4J_PASSWORD="put-password-here"
NEO4J_READY_TIMEOUT=120


# Check if the neo4j port becomes open within a specified interval
check_neo4j_ready() {
    for i in $(seq ${NEO4J_READY_TIMEOUT}); do
        printf "."
        if ss -l | grep "LISTEN.*:${NEO4J_HTTP_PORT}" > /dev/null; then
            return 0
        else
            sleep 1
        fi
    done
    return 1
}

# Fetch neo4j repo key and add to apt
curl -L https://debian.neo4j.org/neotechnology.gpg.key | apt-key add -

# Add neo4j repo to apt
echo 'deb https://debian.neo4j.org/repo stable/' > /etc/apt/sources.list.d/neo4j.list

# Update software repos and install neo4j and monit
apt-get update && apt-get install -y neo4j monit

# Format data device with xfs
mkfs.xfs ${DATA_DEVICE}

# Mount data device
mount ${DATA_DEVICE} ${NEO4J_DATA_DIR}

# Set up peristent mount for /dev/xvdb
chown neo4j:neo4j ${NEO4J_DATA_DIR}
echo "${DATA_DEVICE} ${NEO4J_DATA_DIR}    xfs defaults    0   0" >> /etc/fstab

# Update neo4j data directory
sed -i "s;\(^dbms\.directories\.data=\).*;\1/${NEO4J_DATA_DIR};" /etc/neo4j/neo4j.conf

# Start neo4j and check that its port is open
systemctl start neo4j
check_neo4j_ready || (echo "neo4j failed to start"; exit 1)

# Set neo4j password via curl
curl -H "Content-Type: application/json" -X POST -v \
    -d "{\"password\":\"${NEO4J_PASSWORD}\"}" \
    -u neo4j:neo4j \
    http://localhost:${NEO4J_HTTP_PORT}/user/neo4j/password \
    > /dev/null

# Add constraint to neo4j via curl
curl -H "Content-Type: application/json" -X POST -v \
    --data-binary "@./index.json" \
    -u neo4j:${NEO4J_PASSWORD} \
    http://localhost:${NEO4J_HTTP_PORT}/db/data/transaction/commit \
    > /dev/null

# Configure monit and reload
sed -i "s;# \(set httpd port 2812 and\);\1;" /etc/monit/monitrc
sed -i "s;# \(    use address localhost\);\1;" /etc/monit/monitrc
sed -i "s;# \(    allow localhost\);\1;" /etc/monit/monitrc
sed -i "s;\(Authorization: Basic .*:\);\1${NEO4J_PASSWORD};" ./neo4j
cp ./neo4j /etc/monit/conf.d/
monit reload
