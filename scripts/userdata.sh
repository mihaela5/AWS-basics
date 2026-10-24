#!/bin/bash
set -e

export HOME=/root

echo "Starting CloudShirt worker provisioning..."

# The app runs as a Swarm service; prepare only the shared logs and log shipper.
# Avoid a full dnf update here: it restarts Docker and drops the Swarm node.
dnf install -y amazon-efs-utils

# EFS
mkdir -p /mnt/cloudshirt-logs

# EFS should not prevent the application deployment
# if the filesystem is temporarily unavailable.
if mount -t efs -o tls "${FILE_SYSTEM_ID}:/" /mnt/cloudshirt-logs; then
    echo "EFS mounted successfully."

    # Add EFS to fstab only after a successful mount.
    if ! grep -q "${FILE_SYSTEM_ID}:/" /etc/fstab; then
        echo "${FILE_SYSTEM_ID}:/ /mnt/cloudshirt-logs efs _netdev,tls,nofail 0 0" >> /etc/fstab
    fi
else
    echo "WARNING: EFS mount failed. Continuing CloudShirt deployment."
fi

# Filebeat is optional; disable with ENABLE_FILEBEAT=false.
ENABLE_FILEBEAT="${ENABLE_FILEBEAT:-true}"
if [ "$ENABLE_FILEBEAT" != "true" ]; then
    echo "Skipping Filebeat (ENABLE_FILEBEAT=false)."
    echo "CloudShirt worker provisioning completed successfully."
    exit 0
fi

# Install and configure Filebeat
echo "Installing and configuring Filebeat..."

# A Filebeat failure must not stop the CloudShirt deployment.
FILEBEAT_INSTALLED=false

# Add Elastic repository and import GPG key
rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch

cat << 'EOF' > /etc/yum.repos.d/elastic.repo
[elastic-8.x]
name=Elastic repository for 8.x packages
baseurl=https://artifacts.elastic.co/packages/8.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
EOF

# Try to install Filebeat
if dnf install -y filebeat; then

    FILEBEAT_INSTALLED=true
    echo "Filebeat installed successfully."

    # Write configuration to /etc/filebeat/filebeat.yml
    cat << EOF > /etc/filebeat/filebeat.yml
filebeat.inputs:
  # Container stdout/stderr is written to JSON files on the host.
  - type: filestream
    id: cloudshirt-docker-logs
    enabled: true
    parsers:
      - ndjson:
          target: ""
          message_key: log
          overwrite_keys: true
    paths:
      - /var/lib/docker/containers/*/*-json.log

  # Collect system logs
  - type: filestream
    id: cloudshirt-system-logs
    enabled: true
    paths:
      - /var/log/messages

setup.template.settings:
  index.number_of_shards: 1

setup.kibana:
  host: "${ELASTICSEARCH_PRIVATE_IP}:5601"

output.elasticsearch:
  hosts: ["${ELASTICSEARCH_PRIVATE_IP}:9200"]
  protocol: "http"

processors:
  - add_host_metadata:
      when.not.contains.tags: forwarded
  - add_cloud_metadata: ~
EOF

    # Set appropriate permissions
    chmod 600 /etc/filebeat/filebeat.yml

    echo "Filebeat configured."

else
    echo "WARNING: Filebeat installation failed."
    echo "Continuing without Filebeat."
fi


# Start Filebeat only if installed
if [ "$FILEBEAT_INSTALLED" = true ]; then

    echo "Starting Filebeat..."

    systemctl enable filebeat
    systemctl restart filebeat

else

    echo "Skipping Filebeat service because Filebeat was not installed."

fi

echo "CloudShirt worker provisioning completed successfully."
