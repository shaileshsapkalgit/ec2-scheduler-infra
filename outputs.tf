output "lambda_function_name" {
  description = "Name of the Lambda function (the app pipeline uses this)"
  value       = aws_lambda_function.scheduler.function_name
}

output "lambda_alias_arn" {
  description = "ARN of the live alias that the schedules call"
  value       = aws_lambda_alias.live.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic that sends the reports"
  value       = aws_sns_topic.report.arn
}

output "stop_schedule_name" {
  value = aws_scheduler_schedule.stop.name
}

output "start_schedule_name" {
  value = aws_scheduler_schedule.start.name
}