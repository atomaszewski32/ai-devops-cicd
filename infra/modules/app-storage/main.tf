# Infrastruktura pod quotes-api. Konwencje nazw i tagów: .claude/CLAUDE.md

provider "aws" {
  region = var.region
}

locals {
  prefix = "szkolenie-${var.blok}-${var.uczestnik}"

  tags = {
    Projekt   = "ai-devops-cicd"
    Uczestnik = var.uczestnik
    Blok      = var.blok
    Usuwac    = "tak"
  }
}

data "aws_availability_zones" "dostepne" {
  state = "available"
}

# ── Bucket na artefakty buildów ──────────────────────────────────────

resource "aws_s3_bucket" "artefakty" {
  bucket = "${local.prefix}-artifacts"
  tags   = local.tags
}

resource "aws_s3_bucket_versioning" "artefakty" {
  bucket = aws_s3_bucket.artefakty.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artefakty" {
  bucket = aws_s3_bucket.artefakty.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bez tego zasobu bucket jest prywatny tylko dopóki ktoś nie doda mu polityki.
resource "aws_s3_bucket_public_access_block" "artefakty" {
  bucket = aws_s3_bucket.artefakty.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Artefakty buildów nie są danymi, które trzymamy latami.
resource "aws_s3_bucket_lifecycle_configuration" "artefakty" {
  bucket = aws_s3_bucket.artefakty.id

  rule {
    id     = "usun-stare-artefakty"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# ── Sieć ─────────────────────────────────────────────────────────────

resource "aws_vpc" "glowna" {
  cidr_block           = var.cidr_vpc
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${local.prefix}-vpc" })
}

resource "aws_subnet" "publiczna" {
  vpc_id            = aws_vpc.glowna.id
  cidr_block        = cidrsubnet(var.cidr_vpc, 8, 1)
  availability_zone = data.aws_availability_zones.dostepne.names[0]

  tags = merge(local.tags, { Name = "${local.prefix}-public" })
}

resource "aws_subnet" "prywatna" {
  vpc_id            = aws_vpc.glowna.id
  cidr_block        = cidrsubnet(var.cidr_vpc, 8, 2)
  availability_zone = data.aws_availability_zones.dostepne.names[1]

  tags = merge(local.tags, { Name = "${local.prefix}-private" })
}

resource "aws_internet_gateway" "glowna" {
  vpc_id = aws_vpc.glowna.id
  tags   = merge(local.tags, { Name = "${local.prefix}-igw" })
}

resource "aws_route_table" "publiczna" {
  vpc_id = aws_vpc.glowna.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.glowna.id
  }

  tags = merge(local.tags, { Name = "${local.prefix}-rt-public" })
}

resource "aws_route_table_association" "publiczna" {
  subnet_id      = aws_subnet.publiczna.id
  route_table_id = aws_route_table.publiczna.id
}

# ── Security group aplikacji ─────────────────────────────────────────

resource "aws_security_group" "aplikacja" {
  name        = "${local.prefix}-app"
  description = "Ruch HTTPS do quotes-api"
  vpc_id      = aws_vpc.glowna.id

  tags = merge(local.tags, { Name = "${local.prefix}-app" })
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.aplikacja.id
  description       = "HTTPS z internetu"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# Wyjście zawężone do HTTPS — domyślne "wszystko wszędzie" przechodzi przez skanery,
# ale to właśnie tą drogą wychodzą dane po udanym włamaniu.
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.aplikacja.id
  description       = "Ruch wychodzacy HTTPS - ECR, API AWS"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}
