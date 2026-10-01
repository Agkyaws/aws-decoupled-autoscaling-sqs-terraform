terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

########################
# S3 – Artifact Bucket
########################

resource "aws_s3_bucket" "artifact" {
  bucket = var.bucket_name

  tags = {
    Name        = "${var.project_name}-artifact"
    Environment = "lab"
  }
}

resource "aws_s3_bucket_public_access_block" "artifact" {
  bucket = aws_s3_bucket.artifact.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

########################
# SSM Parameter – Queue Name
########################

resource "aws_ssm_parameter" "queue_name" {
  name  = "/lab/sqs/queue_name"
  type  = "String"
  value = var.queue_name

  tags = {
    Name = "${var.project_name}-queue-name"
  }
}

########################
# SQS Queue
########################

resource "aws_sqs_queue" "lab_queue" {
  name = var.queue_name

  visibility_timeout_seconds = 30

  tags = {
    Name = "${var.project_name}-queue"
  }
}

########################
# Networking – use default VPC
########################

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

########################
# Security Group
########################

resource "aws_security_group" "lab_sg" {
  name        = "${var.project_name}-sg"
  description = "Allow SSH"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Lab only
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

########################
# AMI – Amazon Linux 2023
########################

data "aws_ami" "al2023" {
  most_recent = true

  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

########################
# User Data Templates
########################

data "template_file" "receiver_user_data" {
  template = file("${path.module}/user_data_receiver.sh")

  vars = {
    bucket_name = aws_s3_bucket.artifact.bucket
  }
}

data "template_file" "sender_user_data" {
  template = file("${path.module}/user_data_sender.sh")

  vars = {
    bucket_name = aws_s3_bucket.artifact.bucket
  }
}

########################
# Launch Template – Receiver
########################

resource "aws_launch_template" "receiver_lt" {
  name_prefix   = "${var.project_name}-receiver-"
  image_id      = data.aws_ami.al2023.id
  instance_type = "t2.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  key_name = var.key_pair_name != "" ? var.key_pair_name : null

  network_interfaces {
    security_groups = [aws_security_group.lab_sg.id]
  }

  user_data = base64encode(data.template_file.receiver_user_data.rendered)

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.project_name}-receiver"
      Role = "receiver"
    }
  }
}

########################
# Auto Scaling Group – Receiver
########################

resource "aws_autoscaling_group" "receiver_asg" {
  name                      = "${var.project_name}-receiver-asg"
  max_size                  = var.asg_max_size
  min_size                  = 1
  desired_capacity          = 1
  vpc_zone_identifier       = data.aws_subnets.default.ids
  health_check_type         = "EC2"
  health_check_grace_period = 60

  launch_template {
    id      = aws_launch_template.receiver_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-receiver-asg"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

########################
# Sender EC2 Instance
########################

resource "aws_instance" "sender" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t2.micro"
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.lab_sg.id]

  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  key_name = var.key_pair_name != "" ? var.key_pair_name : null

  user_data = base64encode(data.template_file.sender_user_data.rendered)

  tags = {
    Name = "${var.project_name}-sender"
    Role = "sender"
  }
}

########################
# SNS Topic
########################

resource "aws_sns_topic" "autoscaling_topic" {
  name = "${var.project_name}-autoscaling-topic"
}

########################
# CloudWatch Alarms – SQS
########################

resource "aws_cloudwatch_metric_alarm" "scale_out" {
  alarm_name          = "${var.project_name}-scale-out"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = var.scale_threshold
  alarm_description   = "Scale out when SQS queue depth > threshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.lab_queue.name
  }


  alarm_actions = [
    aws_sns_topic.autoscaling_topic.arn,
    aws_autoscaling_policy.scale_out_policy.arn
  ]

  depends_on = [
    aws_autoscaling_policy.scale_out_policy
  ]
}

resource "aws_cloudwatch_metric_alarm" "scale_in" {
  alarm_name          = "${var.project_name}-scale-in"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = var.scale_threshold
  alarm_description   = "Scale in when SQS queue depth < threshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.lab_queue.name
  }

  alarm_actions = [
    aws_sns_topic.autoscaling_topic.arn,
    aws_autoscaling_policy.scale_in_policy.arn
  ]

  depends_on = [
    aws_autoscaling_policy.scale_in_policy
  ]
}

########################
# Auto Scaling Policies – Simple Scaling
########################

resource "aws_autoscaling_policy" "scale_out_policy" {
  name                   = "${var.project_name}-scale-out-policy"
  autoscaling_group_name = aws_autoscaling_group.receiver_asg.name
  policy_type            = "SimpleScaling"
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 60
}

resource "aws_autoscaling_policy" "scale_in_policy" {
  name                   = "${var.project_name}-scale-in-policy"
  autoscaling_group_name = aws_autoscaling_group.receiver_asg.name
  policy_type            = "SimpleScaling"
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 60
}

########################
# S3 Objects – Upload Python Scripts
########################

resource "aws_s3_object" "send_script" {
  bucket = aws_s3_bucket.artifact.bucket
  key    = "send_messages.py"
  source = "${path.module}/send_messages.py"
  etag   = filemd5("${path.module}/send_messages.py")
}

resource "aws_s3_object" "receive_script" {
  bucket = aws_s3_bucket.artifact.bucket
  key    = "receive_messages.py"
  source = "${path.module}/receive_messages.py"
  etag   = filemd5("${path.module}/receive_messages.py")
}