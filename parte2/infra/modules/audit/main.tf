# Auditoria: trilha CloudTrail multirregiao (mudancas de IAM so chegam a trilhas multirregiao),
# arquivos em S3 com validacao de integridade + copia no CloudWatch Logs para alarmes de seguranca.
data "aws_caller_identity" "me" {}
data "aws_region" "current" {}
data "aws_partition" "p" {}

locals {
  account   = data.aws_caller_identity.me.account_id
  region    = data.aws_region.current.region
  trail     = "${var.name}-trail"
  trail_arn = "arn:${data.aws_partition.p.partition}:cloudtrail:${local.region}:${local.account}:trail/${local.trail}"
}

resource "aws_s3_bucket" "trail" {
  bucket        = "${var.name}-cloudtrail-${local.account}-${local.region}"
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket                  = aws_s3_bucket.trail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule {
    id     = "expira-logs"
    status = "Enabled"
    filter {}
    expiration { days = var.s3_retention_days }
  }
}

data "aws_iam_policy_document" "bucket" {
  statement {
    sid       = "AclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }
  statement {
    sid       = "Write"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail.arn}/AWSLogs/${local.account}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }
  statement {
    sid       = "SomenteTLS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.trail.arn, "${aws_s3_bucket.trail.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket     = aws_s3_bucket.trail.id
  policy     = data.aws_iam_policy_document.bucket.json
  depends_on = [aws_s3_bucket_public_access_block.trail]
}

# Copia dos eventos no CloudWatch Logs (permite filtros de metrica e Logs Insights)
resource "aws_cloudwatch_log_group" "trail" {
  name              = "${var.log_group_prefix}/cloudtrail"
  retention_in_days = var.cwl_retention_days
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }
}

resource "aws_iam_role" "trail_cwl" {
  name               = "${var.name}-cloudtrail-cwl-role"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

data "aws_iam_policy_document" "cwl" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.trail.arn}:log-stream:*"]
  }
}

resource "aws_iam_role_policy" "trail_cwl" {
  name   = "cwl-write"
  role   = aws_iam_role.trail_cwl.id
  policy = data.aws_iam_policy_document.cwl.json
}

resource "aws_cloudtrail" "this" {
  name                          = local.trail
  s3_bucket_name                = aws_s3_bucket.trail.id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.trail_cwl.arn
  depends_on                    = [aws_s3_bucket_policy.trail, aws_iam_role_policy.trail_cwl]
}

# Alarmes de auditoria (padroes do CIS AWS Foundations, adaptados)
locals {
  audit_alarms = {
    iam-policy-change = {
      desc    = "Mudanca em politicas/papeis IAM"
      pattern = "{ ($.eventSource = iam.amazonaws.com) && (($.eventName = PutRolePolicy) || ($.eventName = DeleteRolePolicy) || ($.eventName = AttachRolePolicy) || ($.eventName = DetachRolePolicy) || ($.eventName = CreatePolicyVersion) || ($.eventName = UpdateAssumeRolePolicy)) }"
    }
    sg-change = {
      desc    = "Mudanca em security groups"
      pattern = "{ ($.eventName = AuthorizeSecurityGroupIngress) || ($.eventName = RevokeSecurityGroupIngress) || ($.eventName = AuthorizeSecurityGroupEgress) || ($.eventName = RevokeSecurityGroupEgress) || ($.eventName = CreateSecurityGroup) || ($.eventName = DeleteSecurityGroup) }"
    }
    access-denied = {
      desc    = "Chamadas negadas (AccessDenied/Unauthorized) em sequencia"
      pattern = "{ ($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\") }"
    }
  }
}

resource "aws_cloudwatch_log_metric_filter" "audit" {
  for_each       = local.audit_alarms
  name           = each.key
  log_group_name = aws_cloudwatch_log_group.trail.name
  pattern        = each.value.pattern
  metric_transformation {
    name      = each.key
    namespace = "CC/Audit"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "audit" {
  for_each            = local.audit_alarms
  alarm_name          = "${var.name}-audit-${each.key}"
  alarm_description   = each.value.desc
  namespace           = "CC/Audit"
  metric_name         = each.key
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = each.key == "access-denied" ? 10 : 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]
  depends_on          = [aws_cloudwatch_log_metric_filter.audit]
}
