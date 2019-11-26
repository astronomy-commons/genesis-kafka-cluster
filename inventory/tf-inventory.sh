#!/bin/bash
#
# Generate dynamic ansible inventory
#
# Grab the list of hosts from terraform state. We assume that:
# * the droplet name is the same as the FQDN
# * all Kafka services should be installed on all droplets
#

HOSTS=$(cat terraform.tfstate | jq '[ .modules[].resources[] | select( .type | contains("digitalocean_droplet") ) | .primary.attributes.name ]' -c)

cat <<-EOF
zookeeper:
  hosts: $HOSTS
kafka_broker:
  hosts: $HOSTS
EOF
