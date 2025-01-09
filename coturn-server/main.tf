locals {
  availability_zone = "us-east-2a" # TODO: think about this one
  # coturn_ports = concat([3478, 5349], range(49152, 65536))
  coturn_ports = [3478, 5349]
  external_ports = [3478, 5349]
  internal_ports = [3478]
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
  subnet_id = aws_subnet.public_load_balancer[0].id
  route_table_id = aws_route_table.public_load_balancer_rt.id
}

################ NETWORK LAYER.PRIVATE ########

resource "aws_subnet" "private_coturn_cluster" {
  count = 1
  vpc_id = aws_vpc.coturn_vpc.id
  availability_zone = local.availability_zone
  cidr_block = cidrsubnet(aws_vpc.coturn_vpc.cidr_block, 4, 1)
}

resource "aws_nat_gateway" "private_coturn_cluster_nat" {
  connectivity_type = "private"
  subnet_id         = aws_subnet.private_coturn_cluster[0].id
}

resource "aws_route_table" "private_coturn_cluster_rt" {
  vpc_id = aws_vpc.coturn_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.private_coturn_cluster_nat.id
  }
}

resource "aws_route_table_association" "private_coturn_cluster" {
  subnet_id = aws_subnet.private_coturn_cluster[0].id
  route_table_id = aws_route_table.private_coturn_cluster_rt.id
}

################ EC2 NODES ####################
resource "aws_security_group" "coturn_node_sg" {
  name_prefix = "coturn_node_sg-"
  vpc_id      = aws_vpc.coturn_vpc.id

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.coturn_vpc.cidr_block]
  }
}

resource "aws_iam_role" "ecs_ec2_role" {
  name = "ecs-ec2-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_ec2_role_policy" {
  role       = aws_iam_role.ecs_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ecs_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ecs_ec2_profile" {
  name = "ecs-ec2-instance-profile"
  role = aws_iam_role.ecs_ec2_role.name
}

resource "aws_launch_template" "coturn_ec2_node" {
  name_prefix = "coturn-ec2-node-"
  image_id = "ami-0789039e34e739d67" # Debian 12 (HVM), SSD Volume Type
  instance_type = "t4g.small"
  vpc_security_group_ids = [
    aws_security_group.coturn_node_sg.id
  ]

  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs_ec2_profile.arn
  }

  # user_data = base64encode(<<-EOF
  #     #!/bin/bash
  #     echo ECS_CLUSTER=${aws_ecs_cluster.coturn_cluster.name} >> /etc/ecs/ecs.config;
  #     echo ${locals.turnserver_conf_file} >> ${locals.turnserver_conf_file_host_location}
  #   EOF
  # )
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
  launch_type = "EC2"

  network_configuration {
    security_groups = [aws_security_group.ecs_task.id]
    subnets = [aws_subnet.private_coturn_cluster[0].id]
  }

  dynamic "load_balancer" {
    for_each = aws_lb_target_group.coturn_ecs_service_tg[*]
    content {
      target_group_arn = load_balancer.value.arn
      container_name   = "coturn-server"
      container_port   = load_balancer.value.port
    }
  }

}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "local_file" "coturn_config" {
  content  = local.turnserver_conf_file
  filename = "${path.module}/coturn_config.conf"
}

resource "aws_ecs_task_definition" "coturn_task_definition" {
  family = "coturn-task"
  # source: https://github.com/coturn/coturn/blob/master/docker/coturn/README.md#why-so-many-ports-opened
  # source: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/networking-networkmode-host.html
  # requires_capabilities = ["EC2"]
  network_mode = "host"
  #task_role_arn = "TODO"
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn

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
      essential = true
      mountPoints = [
        {
           sourceVolume = "coturn-config"
           containerPath = "/etc/coturn/turnserver.conf"
           readOnly = true
        }
      ]
    }
  ])

  volume {
    name = "coturn-config"
    host_path = "${path.module}/coturn_config.conf"
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
    for_each = local.coturn_ports
    content {
      protocol    = "tcp"
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

resource "aws_lb" "coturn_ingress_nlb" {
  name               = "coturn-ingress-lb"
  load_balancer_type = "network"
  internal           = false
  subnets            = [aws_subnet.public_load_balancer[0].id]
  security_groups    = [aws_security_group.ingress.id]
}

resource "aws_lb_target_group" "coturn_ecs_service_tg" {
  count       = length(local.coturn_ports)
  name        = "coturn-ecs-service-tg-${local.coturn_ports[count.index]}"
  port        = local.coturn_ports[count.index]
  protocol    = "TCP"
  vpc_id      = aws_vpc.coturn_vpc.id
  target_type = "instance"
}

resource "aws_lb_listener" "coturn_ecs_listeners" {
  count             = length(local.coturn_ports)
  load_balancer_arn = aws_lb.coturn_ingress_nlb.arn
  port              = local.coturn_ports[count.index]
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.coturn_ecs_service_tg[count.index].arn
  }
}
