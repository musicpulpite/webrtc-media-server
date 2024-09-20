locals {
  availability_zone = "us-east-2a" # TODO: think about this one
  turnserver_conf_file_host_location = "/tmp/coturn/turnserver.conf"
  turnserver_conf_file = templatefile("${path.module}/turnserver.conf.tftpl", {
    X="Y"
  })
}

################ NETWORK LAYER ################
resource "aws_vpc" "coturn_vpc" {
  # TODO: consider refactoring to use ipv6 addresses for fun
  cidr_block = "10.10.10.0/24"
  enable_dns_support = true
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "ingress" {
  vpc_id = aws_vpc.coturn_vpc.id
}

resource "aws_eip" "ingress_eip" {
  count = 1
  depends_on = [aws_internet_gateway.ingress]
}

################ NETWORK LAYER.PUBLIC ##########

resource "aws_subnet" "public_load_balancer" {
  count = 1
  vpc_id = aws_vpc.coturn_vpc.id
  availability_zone = local.availability_zone
  cidr_block = cidrsubnet(aws_vpc.coturn_vpc.cidr_block, 4, 0)
  map_public_ip_on_launch = true
}

resource "aws_route_table" "public_load_balancer_rt" {
  vpc_id = aws_vpc.coturn_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ingress.id
  }
}

resource "aws_route_table_association" "public_load_balancer" {
  subnet_id = aws_subnet.public_load_balancer
  route_table_id = aws_route_table.public_load_balancer_rt.id
}

################ NETWORK LAYER.PRIVATE ########

resource "aws_subnet" "private_coturn_cluster" {
  count = 1
  vpc_id = aws_vpc.coturn_vpc.id
  availability_zone = local.availability_zone
  cidr_block = cidrsubnet(aws_vpc.coturn_vpc.cidr_block, 0, 0)
}

resource "aws_nat_gateway" "private_coturn_cluster_nat" {
  connectivity_type = "private"
  subnet_id         = aws_subnet.private_coturn_cluster.id
}

resource "aws_route_table" "private_coturn_cluster_rt" {
  vpc_id = aws_vpc.coturn_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.private_coturn_cluster_nat.id
  }
}

resource "aws_route_table_association" "public_load_balancer" {
  subnet_id = aws_subnet.private_coturn_cluster
  route_table_id = aws_route_table.private_coturn_cluster_rt.id
}

################ EC2 NODES ####################
resource "aws_security_group" "coturn_node_sg" {
  # TODO: create NAT gateway if these nodes will be in private subnet!
  name_prefix = "coturn_node_sg-"
  vpc_id      = aws_vpc.coturn_vpc.id

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_launch_template" "coturn_ec2_node" {
  name_prefix = "coturn-ec2-node-"
  image_id = "ami-0789039e34e739d67" # Debian 12 (HVM), SSD Volume Type
  instance_type = "t4g.small"
  vpc_security_group_ids = [
    aws_security_group.coturn_node_sg.id
  ]

  iam_instance_profile {
    arn = "TODO"
  }

  user_data = base64encode(<<-EOF
      #!/bin/bash
      echo ECS_CLUSTER=${aws_ecs_cluster.coturn_cluster.name} >> /etc/ecs/ecs.config;
      echo ${locals.turnserver_conf_file} >> ${locals.turnserver_conf_file_host_location}
    EOF
  )
}

################ ECS CLUSTER ##################
resource "aws_ecs_cluster" "coturn_cluster" {
  name = "coturn-cluster"
}

resource "aws_ecs_service" "coturn_service" {
  name = "coturn-service"
  cluster = aws_ecs_cluster.coturn_cluster.id
  task_definition = aws_ecs_task_definition.coturn_task_definition.arn
  desired_count = 2

  network_configuration {
    security_groups = [aws_security_group.ecs_task.id]
    subnets = [aws_subnet.private_coturn_cluster.id]
  }
}

resource "aws_ecs_task_definition" "coturn_task_definition" {
  family = "coturn-task"
  # source: https://github.com/coturn/coturn/blob/master/docker/coturn/README.md#why-so-many-ports-opened
  # source: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/networking-networkmode-host.html
  # requires_capabilities = ["EC2"]
  network_mode = "host"
  task_role_arn = "TODO"
  execution_role_arn = "TODO"

  cpu = var.task_cpu
  memory = var.task_memory
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture = "ARM64"
  }
  
  container_definitions = jsonencode([
    {
      name = "coturn-server"
      image = "coturn/coturn:${var.coturn_image_tag}"
      mountPoints = [
        {
           sourceVolume = "coturn-conf"
           containerPath = "/etc/coturn/turnserver.conf"
           readOnly = true
        }
      ]
    }
  ])

  volume {
    name = "coturn-conf"
    host_path = local.turnserver_conf_file_host_location
  }
}

resource "aws_security_group" "ecs_task" {
  name_prefix = "coturn-task-sg-"
  vpc_id      = aws_vpc.coturn_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.coturn_vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

################ LOAD BALANCER INGRESS ########
resource "aws_security_group" "ingress" {
  name = "coturn-ingress"
  description = "Allow ingress on all ports mentioned in documentation https://github.com/coturn/coturn/blob/master/docker/coturn/README.md#why-so-many-ports-opened"
  vpc_id = aws_vpc.coturn_vpc.id

  dynamic "ingress" {
    for_each = concat([3478, 5349], range(49152, 65536))
    content {
      protocol    = "-1"
      from_port   = ingress.value
      to_port     = ingress.value
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "coturn-ingress" {
  name               = "coturn-ingress-elb"
  load_balancer_type = "network"
  subnets            = [aws_subnet.public_load_balancer.id]
  security_groups    = [aws_security_group.ingress.id]
}

# TODO: Target groups
