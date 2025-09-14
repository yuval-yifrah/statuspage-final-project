#!/bin/bash
set -e
exec > >(tee -a /var/log/jenkins-setup.log)
exec 2>&1

echo "=== Starting Jenkins automated setup at $(date) ==="

# Update system
echo "Updating system..."
yum update -y

# Install Git and Docker
echo "Installing Git and Docker..."
yum install -y git docker

# Start Docker
echo "Starting Docker service..."
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# Install Docker Compose - תיקון שיטת ההתקנה
echo "Installing Docker Compose..."
sudo curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verify Docker Compose installation
echo "Verifying Docker Compose installation..."
/usr/local/bin/docker-compose --version

# Create Jenkins directory and clone repo
echo "Setting up Jenkins directory..."
mkdir -p /home/ec2-user/jenkins
cd /home/ec2-user/jenkins

echo "Cloning Jenkins repository..."
git clone ${git_repo_url} .
chown -R ec2-user:ec2-user /home/ec2-user/jenkins

# Wait for Docker to be ready
echo "Waiting for Docker to be ready..."
sleep 15

# Build and start Jenkins with Docker
echo "Starting Jenkins with Docker Compose..."
sudo -u ec2-user bash -c 'cd /home/ec2-user/jenkins && /usr/local/bin/docker-compose up -d'

# Wait for Jenkins to initialize
echo "Waiting for Jenkins to start..."
sleep 60

# Create helper script
cat > /home/ec2-user/jenkins-helper.sh << 'EOF'
#!/bin/bash
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

echo "=== Jenkins Management Helper ==="
echo "Jenkins URL: http://$PUBLIC_IP:8080"
echo ""
echo "Commands:"
echo "1. Get initial admin password:"
echo "   docker logs jenkins 2>&1 | grep -A 5 'Please use the following password'"
echo ""
echo "2. View Jenkins logs:"
echo "   docker logs jenkins"
echo ""
echo "3. Restart Jenkins:"
echo "   cd /home/ec2-user/jenkins && /usr/local/bin/docker-compose restart"
echo ""
echo "Current Jenkins status:"
docker ps | grep jenkins || echo "Jenkins container not found"
EOF

chmod +x /home/ec2-user/jenkins-helper.sh
chown ec2-user:ec2-user /home/ec2-user/jenkins-helper.sh

# Signal completion
touch /home/ec2-user/jenkins-setup-complete

PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo "=== Jenkins setup completed at $(date) ==="
echo "Jenkins URL: http://$PUBLIC_IP:8080"
