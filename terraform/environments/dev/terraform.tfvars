# HelixBeat – Dev Environment Variables
# Update these values to match your AWS account and preferences

aws_region         = "us-east-1"
vpc_cidr           = "10.10.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
kubernetes_version = "1.29"

ecr_repositories = [
  "api",
  "worker",
  "frontend"
]

# Add your email address to receive security alerts
alert_email_addresses = [
  # "your-email@example.com"
]
