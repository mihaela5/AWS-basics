#!/bin/bash
set -e

echo "Starting CloudShirt provisioning..."

# Install dependencies
dnf update -y
dnf install -y git amazon-efs-utils dotnet-sdk-8.0

 
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

 
# Enable and start application
systemctl daemon-reload
systemctl enable cloudshirt
systemctl restart cloudshirt

echo "CloudShirt provisioning completed successfully."