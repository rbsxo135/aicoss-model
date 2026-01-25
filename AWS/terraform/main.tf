terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  name = var.project_name

  input_bucket_name = "input-datas-${data.aws_caller_identity.current.account_id}-${var.region}"

  # remote dirs
  remote_dir_clinical = "/output/Clinical/"
  remote_dir_gene     = "/output/Gene/"
  remote_dir_image    = "/output/Image/"
}

# -------------------------
# Networking (single AZ, private EC2, NAT) - assumes you wanted this earlier.
# Minimal VPC included here; if you already have VPC code, we can plug into existing.
# -------------------------
data "aws_availability_zones" "available" {}

resource "aws_vpc" "this" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "${local.name}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags = { Name = "${local.name}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.20.0.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = { Name = "${local.name}-public" }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false
  tags = { Name = "${local.name}-private" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags = { Name = "${local.name}-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags = { Name = "${local.name}-nat" }
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${local.name}-rt-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "${local.name}-rt-private" }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# VPC endpoints: S3 gateway + interface endpoints for SQS/SSM/etc
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  tags = { Name = "${local.name}-vpce-s3" }
}

resource "aws_security_group" "vpce" {
  name        = "${local.name}-vpce-sg"
  description = "VPC endpoints SG"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

locals {
  interface_endpoints = [
    "sqs",
    "ssm",
    "ec2messages",
    "ssmmessages",
    "logs",
  ]
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(local.interface_endpoints)
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true
  tags = { Name = "${local.name}-vpce-${each.value}" }
}

# -------------------------
# S3 bucket
# -------------------------


resource "aws_s3_bucket" "input" {
  bucket = local.input_bucket_name
}

resource "aws_s3_bucket_notification" "bucket_notifications" {
  bucket = aws_s3_bucket.input.id

  queue {
    queue_arn     = aws_sqs_queue.clinical.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = var.clinical_prefix
  }

  queue {
    queue_arn     = aws_sqs_queue.gene.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = var.gene_prefix
  }

  queue {
    queue_arn     = aws_sqs_queue.image.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = var.image_prefix
  }

  depends_on = [
    aws_sqs_queue_policy.allow_s3_to_send
  ]
}

# -------------------------
# SQS (+ DLQs)
# -------------------------
resource "aws_sqs_queue" "clinical_dlq" {
  name = "${local.name}-clinical-dlq"
}

resource "aws_sqs_queue" "gene_dlq" {
  name = "${local.name}-gene-dlq"
}

resource "aws_sqs_queue" "image_dlq" {
  name = "${local.name}-image-dlq"
}

resource "aws_sqs_queue" "clinical" {
  name                       = "${local.name}-clinical"
  visibility_timeout_seconds  = var.lambda_timeout_seconds + 30
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.clinical_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue" "gene" {
  name                      = "${local.name}-gene"
  visibility_timeout_seconds = var.lambda_timeout_seconds + 30
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.gene_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue" "image" {
  name                      = "${local.name}-image"
  visibility_timeout_seconds = var.image_visibility_timeout_seconds
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.image_dlq.arn
    maxReceiveCount     = 5
  })
}

data "aws_iam_policy_document" "s3_to_sqs" {
  statement {
    sid     = "AllowS3ToSendMessage"
    effect  = "Allow"
    actions = ["sqs:SendMessage"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    resources = [
      aws_sqs_queue.clinical.arn,
      aws_sqs_queue.gene.arn,
      aws_sqs_queue.image.arn
    ]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.input.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "allow_s3_to_send" {
  queue_url = aws_sqs_queue.clinical.id
  policy    = data.aws_iam_policy_document.s3_to_sqs.json
}

resource "aws_sqs_queue_policy" "allow_s3_to_send_gene" {
  queue_url = aws_sqs_queue.gene.id
  policy    = data.aws_iam_policy_document.s3_to_sqs.json
}

resource "aws_sqs_queue_policy" "allow_s3_to_send_image" {
  queue_url = aws_sqs_queue.image.id
  policy    = data.aws_iam_policy_document.s3_to_sqs.json
}

# -------------------------
# Secrets Manager (sftp private key + connection json)
# NOTE: This creates the secret container only. You will put the secret value out-of-band or via TF variable (not recommended).
# -------------------------
resource "aws_secretsmanager_secret" "sftp" {
  name = var.sftp_secret_name
}

# -------------------------
# Lambda IAM + Lambda functions
# -------------------------
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${local.name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn  = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_inline" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion"
    ]
    resources = ["${aws_s3_bucket.input.arn}/*"]
  }

  statement {
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = [aws_secretsmanager_secret.sftp.arn]
  }
}

resource "aws_iam_role_policy" "lambda_inline" {
  name   = "${local.name}-lambda-inline"
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.lambda_inline.json
}

# Lambda zip is expected at ./lambda_build/clinical_gene_lambda.zip (you will build locally)
resource "aws_lambda_function" "clinical" {
  function_name = "${local.name}-clinical"
  role          = aws_iam_role.lambda_role.arn
  runtime       = "python3.9"
  handler       = "handler.lambda_handler"

  filename         = "${path.module}/lambda_build/clinical_gene_lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda_build/clinical_gene_lambda.zip")

  timeout      = var.lambda_timeout_seconds
  memory_size  = var.lambda_memory_mb

  environment {
    variables = {
      MODALITY                = "Clinical"
      INPUT_BUCKET            = local.input_bucket_name
      SFTP_SECRET_ARN         = aws_secretsmanager_secret.sftp.arn
      SFTP_KNOWN_HOSTS_ENTRY  = var.sftp_known_hosts_entry
      SFTP_REMOTE_DIR         = local.remote_dir_clinical
      PREFIX_FOR_FILENAME     = "Clinical_"
    }
  }
}

resource "aws_lambda_function" "gene" {
  function_name = "${local.name}-gene"
  role          = aws_iam_role.lambda_role.arn
  runtime       = "python3.9"
  handler       = "handler.lambda_handler"

  filename         = "${path.module}/lambda_build/clinical_gene_lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda_build/clinical_gene_lambda.zip")

  timeout      = var.lambda_timeout_seconds
  memory_size  = var.lambda_memory_mb

  environment {
    variables = {
      MODALITY                = "Gene"
      INPUT_BUCKET            = local.input_bucket_name
      SFTP_SECRET_ARN         = aws_secretsmanager_secret.sftp.arn
      SFTP_KNOWN_HOSTS_ENTRY  = var.sftp_known_hosts_entry
      SFTP_REMOTE_DIR         = local.remote_dir_gene
      PREFIX_FOR_FILENAME     = "Gene_"
    }
  }
}

# Event source mappings from SQS to Lambda
resource "aws_lambda_event_source_mapping" "clinical" {
  event_source_arn = aws_sqs_queue.clinical.arn
  function_name    = aws_lambda_function.clinical.arn
  batch_size       = 1
}

resource "aws_lambda_event_source_mapping" "gene" {
  event_source_arn = aws_sqs_queue.gene.arn
  function_name    = aws_lambda_function.gene.arn
  batch_size       = 1
}

# -------------------------
# EC2 Image worker (Ubuntu latest via SSM)
# -------------------------
data "aws_ssm_parameter" "ubuntu_2204" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "${local.name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${local.name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role      = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "ec2_inline" {
  statement {
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"]
    resources = [aws_sqs_queue.image.arn]
  }

  statement {
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${aws_s3_bucket.input.arn}/*"]
  }

  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.sftp.arn]
  }

  statement {
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ec2_inline" {
  name   = "${local.name}-ec2-inline"
  role   = aws_iam_role.ec2_role.id
  policy = data.aws_iam_policy_document.ec2_inline.json
}

resource "aws_security_group" "ec2" {
  name        = "${local.name}-ec2-sg"
  description = "Image worker SG (no inbound)"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "image_worker" {
  ami                    = data.aws_ssm_parameter.ubuntu_2204.value
  instance_type          = var.ec2_instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data = templatefile("${path.module}/user_data/image_worker.sh.tftpl", {
    region               = var.region
    queue_url            = aws_sqs_queue.image.id
    bucket_name          = local.input_bucket_name
    sftp_secret_arn      = aws_secretsmanager_secret.sftp.arn
    known_hosts_entry    = var.sftp_known_hosts_entry
    remote_dir_image     = local.remote_dir_image
    image_prefix         = var.image_prefix
  })

  tags = { Name = "${local.name}-image-worker" }
}

