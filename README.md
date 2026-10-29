# ec2-scheduler-infra

Terraform code for the EC2 Scheduler project.

Creates: Lambda function, IAM roles, SNS topic, log group, alias live, and two EventBridge Schedules (stop at 8 PM IST, start at 9 AM IST, Monday to Friday).

The Lambda application code lives in the repo ec2-scheduler-app.
