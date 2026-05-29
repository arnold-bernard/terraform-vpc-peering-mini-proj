resource "aws_vpc" "primary_vpc" {
  cidr_block           = "10.0.0.0/16"
  provider             = aws.primary
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "Primary-VPC-IN-${var.primary_aws_region}"
  }
}

resource "aws_subnet" "primary_subnet" {
  vpc_id                  = aws_vpc.primary_vpc.id
  provider                = aws.primary
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags = {
    Name = "Primary-Subnet"
  }
}

resource "aws_internet_gateway" "primary_igw" {
  vpc_id   = aws_vpc.primary_vpc.id
  provider = aws.primary
  tags = {
    Name = "Primary-IGW"
  }
}

resource "aws_vpc" "secondary_vpc" {
  cidr_block           = "192.168.0.0/16"
  provider             = aws.secondary
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "Secondary-VPC-IN-${var.secondary_aws_region}"
  }
}

resource "aws_subnet" "secondary_subnet" {
  vpc_id                  = aws_vpc.secondary_vpc.id
  provider                = aws.secondary
  cidr_block              = "192.168.1.0/24"
  map_public_ip_on_launch = true
  tags = {
    Name = "Secondary-Subnet"
  }
}

resource "aws_internet_gateway" "secondary_igw" {
  vpc_id   = aws_vpc.secondary_vpc.id
  provider = aws.secondary
  tags = {
    Name = "Secondary-IGW"
  }
}

resource "aws_route_table" "primary_route_table" {
  vpc_id   = aws_vpc.primary_vpc.id
  provider = aws.primary
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.primary_igw.id
  }
}

resource "aws_route_table" "secondary_route_table" {
  vpc_id   = aws_vpc.secondary_vpc.id
  provider = aws.secondary
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.secondary_igw.id
  }
}

resource "aws_route_table_association" "primary_route_table_association" {
  provider       = aws.primary
  route_table_id = aws_route_table.primary_route_table.id
  subnet_id      = aws_subnet.primary_subnet.id
}

resource "aws_route_table_association" "secondary_route_table_association" {
  provider       = aws.secondary
  route_table_id = aws_route_table.secondary_route_table.id
  subnet_id      = aws_subnet.secondary_subnet.id
}

resource "aws_route" "primary_to_secondary_route" {
  provider                  = aws.primary
  route_table_id            = aws_route_table.primary_route_table.id
  destination_cidr_block    = aws_vpc.secondary_vpc.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.peering_connection_primary_to_secondary.id
  depends_on = [
    aws_vpc_peering_connection_accepter.peer_accept
  ]
}

resource "aws_route" "secondary_to_primary_route" {
  provider                  = aws.secondary
  route_table_id            = aws_route_table.secondary_route_table.id
  destination_cidr_block    = aws_vpc.primary_vpc.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.peering_connection_primary_to_secondary.id
  depends_on = [
    aws_vpc_peering_connection_accepter.peer_accept
  ]
}

resource "aws_vpc_peering_connection" "peering_connection_primary_to_secondary" {
  provider    = aws.primary
  peer_vpc_id = aws_vpc.secondary_vpc.id
  vpc_id      = aws_vpc.primary_vpc.id
  peer_region = var.secondary_aws_region
  auto_accept = false
}

resource "aws_vpc_peering_connection_accepter" "peer_accept" {
  provider                  = aws.secondary
  vpc_peering_connection_id = aws_vpc_peering_connection.peering_connection_primary_to_secondary.id
  auto_accept               = true
}

resource "aws_instance" "primary_instance" {
  ami                    = "ami-091138d0f0d41ff90"
  instance_type          = "t2.micro"
  provider               = aws.primary
  key_name               = aws_key_pair.primary_key_pair.key_name
  subnet_id              = aws_subnet.primary_subnet.id
  vpc_security_group_ids = [aws_security_group.primary_instance_sg.id]
  user_data              = <<-EOF
               #!/bin/bash
                apt update -y
                apt install nginx -y
                systemctl enable nginx
                systemctl start nginx
                echo "<h1>Nginx Installed Successfully on $(hostname)</h1>" > /var/www/html/index.html
                EOF
  depends_on             = [aws_vpc_peering_connection.peering_connection_primary_to_secondary]
  tags = {
    Name = "Primary-Instance"
  }
}

resource "aws_security_group" "primary_instance_sg" {
  name        = "primary-instance-sg"
  description = "Allow HTTP and HTTPS traffic from peered VPCs"
  vpc_id      = aws_vpc.primary_vpc.id

  ingress {
    description = "HTTP from primary and secondary VPC"

    from_port = 80
    to_port   = 80
    protocol  = "tcp"

    cidr_blocks = ["0.0.0.0/0",
      aws_vpc.primary_vpc.cidr_block,
      aws_vpc.secondary_vpc.cidr_block
    ]
  }

  ingress {
    description = "SSH from primary and secondary VPC"

    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = ["0.0.0.0/0",
      aws_vpc.primary_vpc.cidr_block,
      aws_vpc.secondary_vpc.cidr_block
    ]
  }

  ingress {
    description = "HTTPS from primary and secondary VPC"

    from_port = 443
    to_port   = 443
    protocol  = "tcp"

    cidr_blocks = [
      aws_vpc.primary_vpc.cidr_block,
      aws_vpc.secondary_vpc.cidr_block
    ]
  }

  egress {
    description = "Allow outbound traffic"

    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "primary-instance-sg"
  }
}

resource "aws_instance" "secondary_instance" {
  ami                    = "ami-0fe18bc3cfa53a248"
  instance_type          = "t2.micro"
  provider               = aws.secondary
  subnet_id              = aws_subnet.secondary_subnet.id
  vpc_security_group_ids = [aws_security_group.secondary_instance_sg.id]
  key_name               = aws_key_pair.secondary_key_pair.key_name
  user_data              = <<-EOF
               #!/bin/bash
                apt update -y
                apt install nginx -y
                systemctl enable nginx
                systemctl start nginx
                echo "<h1>Nginx Installed Successfully on $(hostname)</h1>" > /var/www/html/index.html
                EOF
  depends_on             = [aws_vpc_peering_connection.peering_connection_primary_to_secondary]
  tags = {
    Name = "Secondary-Instance"
  }
}

resource "aws_security_group" "secondary_instance_sg" {
  name        = "secondary-instance-sg"
  description = "Allow HTTP and HTTPS traffic from peered VPCs"
  vpc_id      = aws_vpc.secondary_vpc.id
  provider    = aws.secondary
  ingress {
    description = "HTTP from primary and secondary VPC"

    from_port = 80
    to_port   = 80
    protocol  = "tcp"

    cidr_blocks = ["0.0.0.0/0", aws_vpc.primary_vpc.cidr_block, aws_vpc.secondary_vpc.cidr_block]
  }
  ingress {
    description = "SSH from primary and secondary VPC"

    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = ["0.0.0.0/0",
      aws_vpc.primary_vpc.cidr_block,
      aws_vpc.secondary_vpc.cidr_block
    ]
  }

  ingress {
    description = "HTTPS from primary and secondary VPC"

    from_port = 443
    to_port   = 443
    protocol  = "tcp"

    cidr_blocks = [
      aws_vpc.primary_vpc.cidr_block,
      aws_vpc.secondary_vpc.cidr_block
    ]
  }

  egress {
    description = "Allow outbound traffic"

    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "secondary-instance-sg"
  }
}

resource "aws_key_pair" "primary_key_pair" {
  key_name   = "primary-key"
  public_key = file("F:\\Study\\Terraform\\Piyush_Terraform\\day15\\primary-key.pub")
}

resource "aws_key_pair" "secondary_key_pair" {
  provider   = aws.secondary
  key_name   = "secondary-key"
  public_key = file("F:\\Study\\Terraform\\Piyush_Terraform\\day15\\secondary-key.pub")
}