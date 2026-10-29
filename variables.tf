variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
}

variable "environment" {
  description = "Environment name, for example dev or prod"
  type        = string
}

variable "project_name" {
  description = "Project name, used as the prefix for resource names"
  type        = string
  default     = "ec2-scheduler"
}

variable "notification_email" {
  description = "Email address that receives the start/stop reports"
  type        = string
}

variable "schedule_tag_key" {
  description = "Tag key that marks instances managed by the scheduler"
  type        = string
  default     = "Schedule"
}

variable "schedule_tag_value" {
  description = "Tag value that marks instances managed by the scheduler"
  type        = string
  default     = "office-hours"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}