###############################################################################
# HelixBeat – Route 53 Module
# Provisions:
#   • Public hosted zone (external DNS resolution)
#   • Private hosted zone (internal VPC resolution)
#   • Health check and ALB alias records (conditional – only when alb_dns_name
#     is provided). Environments call this module WITHOUT ALB inputs to break
#     the circular dependency chain (route53 → documentdb → ec2 → alb → acm
#     → route53). Alias records and the health check are then created as inline
#     resources in the environment main.tf.
###############################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Public hosted zone
# ---------------------------------------------------------------------------
resource "aws_route53_zone" "public" {
  name    = var.domain_name
  comment = "HelixBeat ${var.environment} public zone"

  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-public-zone" })
}

# ---------------------------------------------------------------------------
# Private hosted zone (internal service discovery)
# ---------------------------------------------------------------------------
resource "aws_route53_zone" "private" {
  name    = "internal.${var.domain_name}"
  comment = "HelixBeat ${var.environment} private zone"

  vpc {
    vpc_id = var.vpc_id
  }

  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-private-zone" })
}

# ---------------------------------------------------------------------------
# Health Check – Primary ALB endpoint
# Only created when alb_dns_name is provided. When called without ALB inputs
# (the standard per-environment pattern), the health check is an inline
# resource in the environment main.tf to avoid the circular dependency.
# ---------------------------------------------------------------------------
resource "aws_route53_health_check" "primary" {
  count = var.alb_dns_name != "" ? 1 : 0

  fqdn              = var.alb_dns_name
  port              = 443
  type              = "HTTPS"
  resource_path     = var.health_check_path
  failure_threshold = 3
  request_interval  = 30

  enable_sni = true

  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-hc-primary" })
}

# ---------------------------------------------------------------------------
# Public A record → ALB alias (conditional)
# ---------------------------------------------------------------------------
resource "aws_route53_record" "apex" {
  count = var.alb_dns_name != "" ? 1 : 0

  zone_id = aws_route53_zone.public.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wildcard" {
  count = var.alb_dns_name != "" ? 1 : 0

  zone_id = aws_route53_zone.public.zone_id
  name    = "*.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# ---------------------------------------------------------------------------
# Private CNAME records for internal services (e.g. DocumentDB)
# Passed via var.internal_dns_records. When empty (default) nothing is created.
# Environments that would create a circular dep pass {} here and create the
# records as inline aws_route53_record resources in main.tf instead.
# ---------------------------------------------------------------------------
resource "aws_route53_record" "internal_services" {
  for_each = var.internal_dns_records

  zone_id = aws_route53_zone.private.zone_id
  name    = "${each.key}.internal.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60
  records = [each.value]
}
