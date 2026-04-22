provider "aws" {
  region = "us-west-2"
}

variable "server_port" {
  description = "The port on which the server will listen"
  default     = 8080
  type = number
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "web_server_sg" {
  name        = "web-server-sg"
  description = "Allow HTTP traffic"

  // Allow SSH access for management (optional, consider restricting to specific IPs for security)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # or your IP for more security
  }

  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
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

resource "aws_security_group" "ALB_sg" {
  name        = "alb-sg"
  description = "Allow HTTP traffic to ALB"

  ingress {
    from_port   = 80
    to_port     = 80
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

resource "aws_launch_template" "WebServerLaunchTemplate" {
  image_id  = "ami-0cc96c4cd98401dae"
  instance_type = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]

  tags = {
    Name = "ExampleInstance"
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              mkdir -p /www
              echo "Hello, World!" > /var/www/index.html
              nohup python3 -m http.server ${var.server_port} &
              EOF
  )

  lifecycle {
    create_before_destroy = true
  }

}

resource "aws_autoscaling_group" "WebServerASG" {
  name                      = "web-server-asg"
  vpc_zone_identifier = data.aws_subnets.default.ids
  target_group_arns = [aws_lb_target_group.web_server_tg.arn]
  health_check_type = "ELB"

  max_size                  = 3
  min_size                  = 1
  desired_capacity          = 2
  launch_template {
    id      = aws_launch_template.WebServerLaunchTemplate.id
    version = "$Latest"
  }
  tag {
    key                 = "Name"
    value               = "WebServerInstance"
    propagate_at_launch = true
  }

}

resource "aws_lb" "web_server_lb" {
  name               = "web-server-lb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ALB_sg.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "web_server_tg" {
  name     = "web-server-tg"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "web_server_listener" {
  load_balancer_arn = aws_lb.web_server_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404: Page not found."
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "web_server_listener_rule" {
  listener_arn = aws_lb_listener.web_server_listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_server_tg.arn
  }

  condition {
    path_pattern {
      values = ["*"]
    }
  }
}

output "load_balancer_dns_name" {
  value = aws_lb.web_server_lb.dns_name
  description = "The domain name of the ALB."
}