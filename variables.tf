variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix for all resources"
  type        = string
  default     = "sqs-asg-lab"
}

variable "queue_name" {
  description = "SQS queue name (must match SSM parameter value)"
  type        = string
  default     = "lab-sqs-queue"
}

variable "bucket_name" {
  description = "S3 bucket for scripts (must be globally unique)"
  type        = string
  default     = "sqs-lab-artifact-28374-demo"
}

variable "key_pair_name" {
  description = "Existing EC2 key pair name (optional)"
  type        = string
  default     = ""
}

variable "asg_max_size" {
  description = "Max size for receiver Auto Scaling Group (sandbox friendly)"
  type        = number
  default     = 3
}

variable "scale_threshold" {
  description = "SQS visible messages threshold for scale in/out"
  type        = number
  default     = 200
}