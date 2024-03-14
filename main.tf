provider "aws" {
  alias  = "eu"
  region = "eu-central-1"
}

## Create bucket
resource "aws_s3_bucket" "s3-georgik16-123-bucket" {
  bucket = var.bucket_name
  tags = {
    Environment = "${var.env}"
  }
}

## Assign policy to allow CloudFront to reach S3 bucket
resource "aws_s3_bucket_policy" "origin" {
  depends_on = [
    aws_cloudfront_distribution.Site_Access
  ]
  bucket = aws_s3_bucket.s3-georgik16-123-bucket.id
  policy = data.aws_iam_policy_document.origin.json
}

## Create policy to allow CloudFront to reach S3 bucket
data "aws_iam_policy_document" "origin" {
  depends_on = [
    aws_cloudfront_distribution.Site_Access,
    aws_s3_bucket.s3-georgik16-123-bucket
  ]
  statement {
    sid    = "3"
    effect = "Allow"
    actions = [
      "s3:GetObject"
    ]
    principals {
      identifiers = ["cloudfront.amazonaws.com"]
      type        = "Service"
    }
    resources = [
      "arn:aws:s3:::${aws_s3_bucket.s3-georgik16-123-bucket.bucket}/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"

      values = [
        aws_cloudfront_distribution.Site_Access.arn
      ]
    }
  }
}

## Enable AWS S3 file versioning
resource "aws_s3_bucket_versioning" "Site_Origin" {
  bucket = aws_s3_bucket.s3-georgik16-123-bucket.bucket
  versioning_configuration {
    status = "Enabled"
  }
}

## Upload file to S3 bucket
resource "aws_s3_object" "content" {
  depends_on = [
    aws_s3_bucket.s3-georgik16-123-bucket
  ]
  bucket                 = aws_s3_bucket.s3-georgik16-123-bucket.bucket
  key                    = "index.html"
  source                 = "./index.html"
  server_side_encryption = "AES256"

  content_type = "text/html"
}

## Create CloudFront distrutnion group
resource "aws_cloudfront_distribution" "Site_Access" {
  depends_on = [
    aws_s3_bucket.s3-georgik16-123-bucket,
    aws_cloudfront_origin_access_control.Site_Access
  ]

  origin {
    domain_name              = aws_s3_bucket.s3-georgik16-123-bucket.bucket_regional_domain_name
    origin_id                = aws_s3_bucket.s3-georgik16-123-bucket.id
    origin_access_control_id = aws_cloudfront_origin_access_control.Site_Access.id
  }

  enabled             = true
  default_root_object = "index.html"
  aliases             = [var.domain_name]

  custom_error_response {
    error_caching_min_ttl = 3000
    error_code            = 404
    response_code         = 200
    response_page_path    = "./index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["BG"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = aws_s3_bucket.s3-georgik16-123-bucket.id
    viewer_protocol_policy = "https-only"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }

    }
  }

  viewer_certificate {
    # cloudfront_default_certificate = true
    acm_certificate_arn = aws_acm_certificate.cert.arn
    ssl_support_method  = "sni-only"
  }
}


## Create Origin Access Control as this is required to allow access to the s3 bucket without public access to the S3 bucket.
resource "aws_cloudfront_origin_access_control" "Site_Access" {
  name                              = "Security_Pillar100_CF_S3_OAC"
  description                       = "OAC setup for security pillar 100"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

#Create a route53 hosted zone
resource "aws_route53_zone" "example" {
  name = var.domain_name
}

#Create A record for S3 static website
resource "aws_route53_record" "example_domain-a" {
  zone_id = aws_route53_zone.example.zone_id
  type    = "A"
  name    = var.domain_name
  alias {
    name                   = aws_cloudfront_distribution.Site_Access.domain_name
    zone_id                = aws_cloudfront_distribution.Site_Access.hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "cert_validation" {
  count   = length(aws_acm_certificate.cert.domain_validation_options)
  name    = element(aws_acm_certificate.cert.domain_validation_options.*.resource_record_name, count.index)
  type    = element(aws_acm_certificate.cert.domain_validation_options.*.resource_record_type, count.index)
  zone_id = aws_route53_zone.example.zone_id
  records = [element(aws_acm_certificate.cert.domain_validation_options.*.resource_record_value, count.index)]
  ttl     = 60
}