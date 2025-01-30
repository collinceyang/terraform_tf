# AWS Provider Configuration
provider "aws" {
  region = var.region
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "my-vpc"
  }
}

# Create Subnets with Public IP Auto-Assignment
resource "aws_subnet" "subnet1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr[0]
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true  # Enable public IP assignment

  tags = {
    Name = "subnet-1"
  }
}

resource "aws_subnet" "subnet2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr[1]
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = true  # Enable public IP assignment

  tags = {
    Name = "subnet-2"
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "my-gateway"
  }
}

# Route table to allow internet access
resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "route-table"
  }
}

# Associate the Route Table with Subnets
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.route_table.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.subnet2.id
  route_table_id = aws_route_table.route_table.id
}

# Security Group for ALB and EC2 Instances
resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow SSH from anywhere (consider restricting it)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-sg"
  }
}


# Launch EC2 Instances with application
resource "aws_instance" "web1" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.subnet1.id
  associate_public_ip_address = true  # Ensure public IP assignment
  security_groups        = [aws_security_group.alb_sg.id]
  key_name = "awsdemo"  # Use the name of your key pair here (without .pem)  Specify the key pair name here

  # User Data to install application
  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y git python3 python3-venv python3-pip
              sudo rm -rf /opt/lkgsmklab
              sudo git clone --depth=1 https://github.com/collinceyang/lkgsmklab.git /opt/lkgsmklab
              cd /opt/lkgsmklab
              sudo chown -R ec2-user:ec2-user /opt/lkgsmklab
              python3 -m venv /opt/lkgsmklab
              source /opt/lkgsmklab/bin/activate
              pip install --upgrade pip
              pip install -r requirements.txt
              sudo ./bin/uvicorn app:app --host 0.0.0.0 --port 80 --workers 4
              
              # # Create a systemd service for uvicorn
              # sudo bash -c 'cat > /etc/systemd/system/lkgsmklab.service <<EOL
              # [Unit]
              # Description=FastAPI Uvicorn App
              # After=network.target

              # [Service]
              # User=ec2-user
              # WorkingDirectory=/opt/lkgsmklab
              # Environment="PATH=/opt/lkgsmklab/bin"
              # ExecStart=/opt/lkgsmklab/bin/uvicorn app:app --host 0.0.0.0 --port 80 --workers 4
              # Restart=always

              # [Install]
              # WantedBy=multi-user.target
              # EOL'
              # # Reload systemd, enable and start the service
              # sudo systemctl daemon-reload
              # sudo systemctl enable lkgsmklab
              # sudo systemctl start lkgsmklab
              EOF

  tags = {
    Name = "web-1"
  }
}

resource "aws_instance" "web2" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.subnet2.id
  associate_public_ip_address = true  # Ensure public IP assignment
  security_groups        = [aws_security_group.alb_sg.id]
  key_name = "awsdemo"  # Use the name of your key pair here (without .pem)

  # User Data to install Nginx
  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y git python3 python3-venv python3-pip
              sudo rm -rf /opt/lkgsmklab
              sudo git clone --depth=1 https://github.com/collinceyang/lkgsmklab.git /opt/lkgsmklab
              cd /opt/lkgsmklab
              sudo chown -R ec2-user:ec2-user /opt/lkgsmklab
              python3 -m venv /opt/lkgsmklab
              source /opt/lkgsmklab/bin/activate
              pip install --upgrade pip
              pip install -r requirements.txt
              sudo ./bin/uvicorn app:app --host 0.0.0.0 --port 80 --workers 4
              EOF

  tags = {
    Name = "web-2"
  }
}

# Create Application Load Balancer (ALB)
resource "aws_lb" "app_lb" {
  name               = "my-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]

  tags = {
    Name = "app-lb"
  }
}

# Create Target Group
resource "aws_lb_target_group" "tg" {
  name     = "my-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/list_sut"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Attach EC2 Instances to Target Group
resource "aws_lb_target_group_attachment" "attach1" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "attach2" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web2.id
  port             = 80
}

# ALB Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}