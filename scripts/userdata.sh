#!/bin/bash
set -e

echo "Starting CloudShirt provisioning..."

# Install dependencies
dnf update -y
dnf install -y git amazon-efs-utils dotnet-sdk-8.0

echo "Installing and configuring Filebeat..."

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

# Install Filebeat
dnf install -y filebeat

# Write configuration to /etc/filebeat/filebeat.yml
cat << EOF > /etc/filebeat/filebeat.yml
filebeat.inputs:
  # Collect CloudShirt application logs from the mounted EFS directory
  - type: filestream
    id: cloudshirt-efs-logs
    enabled: true
    paths:
      - /mnt/cloudshirt-logs/*.log
    parsers:
      - ndjson:
          target: ""
          overwrite_keys: true

  # Collect systemd / console output logs
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

# Set appropriate permissions and start Filebeat
chmod 600 /etc/filebeat/filebeat.yml

echo "Filebeat configured."
 
# EFS
mkdir -p /mnt/cloudshirt-logs

# EFS should not prevent the application deployment
# if the filesystem is temporarily unavailable.
if mount -t efs -o tls "${FILE_SYSTEM_ID}:/" /mnt/cloudshirt-logs; then
    echo "EFS mounted successfully."

    # Add EFS to fstab only after a successful mount.
    if ! grep -q "${FILE_SYSTEM_ID}:/" /etc/fstab; then
        echo "${FILE_SYSTEM_ID}:/ /mnt/cloudshirt-logs efs _netdev,tls 0 0" >> /etc/fstab
    fi
else
    echo "WARNING: EFS mount failed. Continuing CloudShirt deployment."
fi

 
# Download CloudShirt
cd /opt

if [ ! -d "/opt/CloudShirt" ]; then
    git clone https://github.com/looking4ward/CloudShirt.git
fi

cd /opt/CloudShirt/src/Web

 
# Configure Amazon RDS
sed -i \
's|Server=(localdb)\\\\mssqllocaldb;Integrated Security=true;Initial Catalog=Microsoft.eShopOnWeb.CatalogDb;|Server='"${DB_ENDPOINT}"','"${DB_PORT}"';User ID='"${DB_USERNAME}"';Password='"${DB_PASSWORD}"';Initial Catalog=Microsoft.eShopOnWeb.CatalogDb;TrustServerCertificate=True;|' \
appsettings.json

sed -i \
's|Server=(localdb)\\\\mssqllocaldb;Integrated Security=true;Initial Catalog=Microsoft.eShopOnWeb.Identity;|Server='"${DB_ENDPOINT}"','"${DB_PORT}"';User ID='"${DB_USERNAME}"';Password='"${DB_PASSWORD}"';Initial Catalog=Microsoft.eShopOnWeb.Identity;TrustServerCertificate=True;|' \
appsettings.json

 
# Publish CloudShirt
mkdir -p /opt/cloudshirt/release

dotnet publish \
    -c Release \
    -o /opt/cloudshirt/release

 
# Create systemd service
cat > /etc/systemd/system/cloudshirt.service <<'EOF'
[Unit]
Description=CloudShirt ASP.NET Core Application
After=network.target

[Service]
WorkingDirectory=/opt/cloudshirt/release
ExecStart=/usr/bin/dotnet /opt/cloudshirt/release/Web.dll

Restart=always
RestartSec=10

KillSignal=SIGINT
SyslogIdentifier=cloudshirt

User=root

Environment=ASPNETCORE_ENVIRONMENT=Development
Environment=ASPNETCORE_URLS=http://0.0.0.0:80

[Install]
WantedBy=multi-user.target
EOF

 
# Enable and start application and filebeat
systemctl daemon-reload
systemctl enable cloudshirt
systemctl restart cloudshirt
systemctl enable filebeat
systemctl restart filebeat

echo "CloudShirt provisioning completed successfully."