locals {
  elasticache_port = 6389
}

resource "aws_vpc" "sdp_signalling_server" {
  cidr_block           = "12.0.0.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = true

}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.sdp_signalling_server.id
  availability_zone       = "us-east-2a"
  cidr_block              = cidrsubnet(aws_vpc.sdp_signalling_server.cidr_block, 2, 0)
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.sdp_signalling_server.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.sdp_signalling_server.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "elasticache" {
  name   = "elasticache-security-group"
  vpc_id = aws_vpc.sdp_signalling_server.id

  # Redis port
  ingress {
    from_port   = local.elasticache_port
    to_port     = local.elasticache_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "elasticache-subnet-group"
  subnet_ids = [aws_subnet.public.id]
}

resource "aws_elasticache_parameter_group" "main" {
  family = "redis7"
  name   = "sdp-signalling-server-params"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "sdp-signalling-server"
  description          = "placeholder"
  node_type            = "cache.t3.micro"
  port                 = local.elasticache_port
  parameter_group_name = aws_elasticache_parameter_group.main.name
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [aws_security_group.elasticache.id]

  # Enable encryption in transit
  transit_encryption_enabled = true
  auth_token                 = var.elasticache_auth_token

  automatic_failover_enabled = false
  num_cache_clusters         = 1
}
