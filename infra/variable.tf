variable "function_name" {
  description = "lambda function name"
  default     = "jira-backup"
}

variable "lambda_runtime" {
  description = "lambda runtime"
  default     = "python3.8"
}

variable "ssm_prefix_path" {
  description = "prefix path of parameter store for jira backup"
  default     = "/jira-backup"
}

variable "slack_channel" {
  description = "slack channel name"
  default     = "#backup-notification"
}

variable "slack_username" {
  type        = string
  description = "slack username"
  default     = "jira-backup"
}

variable "s3_bucket_name" {
  type        = string
  description = "jira backup bucket name"
}

variable "extra_env_vars" {
  type        = map(any)
  default     = {}
  description = "lambda extra environment variables"
}

variable "schedule_expression" {
  type    = string
  default = "cron(30 21 ? * MON,THU *)" # weekly every monday,thursday 21:30 utc time
}

variable "lambda_timeout" {
  type        = number
  description = "lambda timeout in seconds"
  default     = 300 # maxium is 900(15 mins) if the backup is very big
}
variable "create_s3_bucket" {
  type        = bool
  description = "if true a backup bucket will be created"
  default     = true
}

variable "enable_s3_lifecycle" {
  type        = string
  description = "if true jira backup will expire after specific time"
  default     = "Enabled"
}

variable "expired_in_days" {
  type        = number
  description = "in days the backup object in s3 will be deleted"
  default     = 30
}
