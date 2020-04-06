provider "aws" {
  region = "ap-northeast-2"
  access_key = "AKIAUIEUQ6C2WT6C6VRD"
  secret_key = "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"
}

##################################################
##################################################

resource "aws_vpc" "stage_vpc" {
  cidr_block  = "10.10.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
  instance_tenancy = "default"

  tags = {
    Name = "stage"
  }
}

resource "aws_default_route_table" "stage" {
  default_route_table_id = aws_vpc.stage_vpc.default_route_table_id
  tags = {
    Name = "default"
  }
}

##################################################
// public subnets
##################################################

resource "aws_subnet" "public_subnet1" {
  vpc_id = aws_vpc.stage_vpc.id
  cidr_block = "10.10.77.0/24"
  map_public_ip_on_launch = false
  availability_zone = data.aws_availability_zones.available.names[0]
  #availability_zone = data.aws_availability_zone.all.name

  tags = {
    Name = "public-az-1"
  }
}

resource "aws_subnet" "public_subnet2" {
  vpc_id = aws_vpc.stage_vpc.id
  cidr_block = "10.10.78.0/24"
  map_public_ip_on_launch = false
  availability_zone = data.aws_availability_zones.available.names[1]


  tags = {
    Name = "public-az-2"
  }
}

##################################################
// private subnets
##################################################

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "private_subnet1" {
  vpc_id = aws_vpc.stage_vpc.id
  cidr_block = "10.10.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  #availability_zone   = data.aws_availability_zone.all.name
  tags = {
    Name = "private-az-1"
  }
}


resource "aws_subnet" "private_subnet2" {
  vpc_id = aws_vpc.stage_vpc.id
  cidr_block = "10.10.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  #availability_zone   = data.aws_availability_zone.all.name
  tags = {
    Name = "private-az-2"
  }
}

##################################################
// IGW, ROUTING, NAT
##################################################

resource "aws_internet_gateway" "stage_igw" {
  vpc_id = aws_vpc.stage_vpc.id
  tags = {
    Name = "internet-gateway"
  }
}

// route to internet
resource "aws_route" "stage_internet_access" {
  route_table_id = aws_vpc.stage_vpc.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.stage_igw.id
}

// elastic IP for NAT
resource "aws_eip" "stage_nat_eip" {
  vpc = true
  depends_on = [aws_internet_gateway.stage_igw]
}

// NAT gateway
resource "aws_nat_gateway" "stage_nat" {
  allocation_id = aws_eip.stage_nat_eip.id
  subnet_id = aws_subnet.public_subnet1.id
  depends_on = [aws_internet_gateway.stage_igw]
}

// private route table
resource "aws_route_table" "stage_private_route_table" {
  vpc_id = aws_vpc.stage_vpc.id
  tags = {
    Name = "private"
  }
}

resource "aws_route" "private_route" {
  route_table_id = aws_route_table.stage_private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.stage_nat.id
}


// associate subnets to route tables
resource "aws_route_table_association" "stage_public_subnet1_association" {
  subnet_id = aws_subnet.public_subnet1.id
  route_table_id = aws_vpc.stage_vpc.main_route_table_id
}

resource "aws_route_table_association" "stage_public_subnet2_association" {
  subnet_id = aws_subnet.public_subnet2.id
  route_table_id = aws_vpc.stage_vpc.main_route_table_id
}

resource "aws_route_table_association" "stage_private_subnet1_association" {
  subnet_id = aws_subnet.private_subnet1.id
  route_table_id = aws_route_table.stage_private_route_table.id
}

resource "aws_route_table_association" "stage_private_subnet2_association" {
  subnet_id = aws_subnet.private_subnet2.id
  route_table_id = aws_route_table.stage_private_route_table.id
}


##################################################
// default security group
##################################################

resource "aws_default_security_group" "stage_default" {
  vpc_id = aws_vpc.stage_vpc.id

  ingress {
    protocol  = -1
    self      = true
    from_port = 0
    to_port   = 0
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "default"
  }
}

resource "aws_default_network_acl" "stage_default" {
  default_network_acl_id = aws_vpc.stage_vpc.default_network_acl_id

  ingress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "default"
  }
}


// network acl for public subnets
resource "aws_network_acl" "public" {
  vpc_id = aws_vpc.stage_vpc.id
  subnet_ids = [
    aws_subnet.public_subnet1.id,
    aws_subnet.public_subnet2.id,
  ]

  tags = {
    Name = "public"
  }
}



// Basiton Host
resource "aws_security_group" "stage_bastion" {
  name = "bastion"
  description = "Security group for bastion instance"
  vpc_id = aws_vpc.stage_vpc.id

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastion"
  }
}

resource "aws_instance" "stage_bastion" {
  ami = "ami-0e5ec6ec0e7672e12"
  availability_zone = aws_subnet.public_subnet1.availability_zone
  instance_type = "t2.nano"
  #key_name = "YOUR-KEY-PAIR-NAME"
  vpc_security_group_ids = [
    aws_default_security_group.stage_default.id,
    aws_security_group.stage_bastion.id
  ]
  subnet_id = aws_subnet.public_subnet1.id
  associate_public_ip_address = true

  tags = {
    Name = "bastion"
  }
}

resource "aws_eip" "stage_bastion" {
  vpc = true
  instance = aws_instance.stage_bastion.id
  depends_on = [aws_internet_gateway.stage_igw]
}



##################################################
##################################################


output "public_ip" {
  #value = "${aws_elb.example.dns_name}"
  value = aws_instance.stage_bastion.public_ip
}
