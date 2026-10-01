output "sqs_queue_url" {
  description = "URL of the SQS queue"
  value       = aws_sqs_queue.lab_queue.id
}

output "sqs_queue_name" {
  description = "Name of the SQS queue"
  value       = aws_sqs_queue.lab_queue.name
}

output "artifact_bucket_name" {
  description = "S3 bucket used for scripts"
  value       = aws_s3_bucket.artifact.bucket
}

output "receiver_asg_name" {
  description = "Name of the receiver Auto Scaling Group"
  value       = aws_autoscaling_group.receiver_asg.name
}

output "sender_instance_id" {
  description = "ID of the sender EC2 instance"
  value       = aws_instance.sender.id
}