#!/bin/bash
set -e

export HOME=/root
export DOTNET_CLI_HOME=/root

echo "Starting CloudShirt provisioning..."

# Install dependencies
dnf update -y
dnf install -y git amazon-efs-utils dotnet-sdk-8.0 logrotate


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

# Each instance writes its logs to its own directory on the shared EFS.
# One shared log file would interleave the output of all instances and make
# every instance's log rotation fight over the same file.
INSTANCE_NAME="$(hostname -s 2>/dev/null || uname -n)"

 
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

 
# Wrapper that appends the application output to the log file on EFS.
# It keeps the logs of every instance in its own directory, because all
# instances share the same EFS filesystem.
cat > /opt/cloudshirt/run.sh <<'EOF'
#!/bin/bash
LOG_DIR="/mnt/cloudshirt-logs/$(hostname -s 2>/dev/null || uname -n)"

if ! mountpoint -q /mnt/cloudshirt-logs; then
    echo "WARNING: /mnt/cloudshirt-logs is not mounted; writing logs to local disk." >&2
fi

mkdir -p "$LOG_DIR"
exec /usr/bin/dotnet /opt/cloudshirt/release/Web.dll >> "$LOG_DIR/app.log" 2>&1
EOF

chmod +x /opt/cloudshirt/run.sh

# Create systemd service
cat > /etc/systemd/system/cloudshirt.service <<'EOF'
[Unit]
Description=CloudShirt ASP.NET Core Application
# Wait for the EFS mount from fstab so the log directory is really the EFS
# filesystem. A failed mount does not block the application: availability
# wins over logging.
After=network.target remote-fs.target

[Service]
WorkingDirectory=/opt/cloudshirt/release
ExecStart=/opt/cloudshirt/run.sh

Restart=always
RestartSec=10

KillSignal=SIGINT

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

echo "CloudShirt service started."


# Rotate the application log daily on EFS (REQ-03: log files stored on a
# daily basis). logrotate renames the current log file to app.log-YYYY-MM-DD
# and creates a new app.log; the service restart lets the application reopen it.
# dateyesterday names the file after the day the logs were written, because
# rotation runs shortly after midnight.
cat > /etc/logrotate.d/cloudshirt << EOF
/mnt/cloudshirt-logs/${INSTANCE_NAME}/app.log {
    daily
    dateext
    dateyesterday
    dateformat -%Y-%m-%d
    rotate 7
    missingok
    notifempty
    create 0644 root root

    postrotate
        systemctl restart cloudshirt.service
    endscript
}
EOF

# On Amazon Linux 2023 logrotate is triggered by a systemd timer.
if systemctl cat logrotate.timer >/dev/null 2>&1; then
    systemctl enable --now logrotate.timer
else
    echo "WARNING: logrotate.timer not found; verify that daily log rotation is triggered."
fi


# Install Filebeat AFTER CloudShirt
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
  # Collect the application logs of this instance from the mounted EFS directory.
  # Only the instance's own directory is read: all instances see the complete
  # shared EFS, so reading every directory would index each line multiple times.
  - type: filestream
    id: cloudshirt-efs-logs
    enabled: true
    paths:
      - /mnt/cloudshirt-logs/${INSTANCE_NAME}/app.log*

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

echo "CloudShirt provisioning completed successfully."