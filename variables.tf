variable "env" {
  description = "Variable used to define environment"
  type        = string
  default     = "lab"
}

variable "bucket_name" {
  description = "The name of the S3 bucket"
  default     = "s3-georgik16-123-bucket"
}