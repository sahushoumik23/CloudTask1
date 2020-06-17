//aws provider
provider "aws" {
  region     = "ap-south-1"
  profile    = "task1"
}

resource "tls_private_key" "pkey" {
  algorithm  = "RSA"
}

resource "aws_key_pair" "webkey1" {
  key_name   = "webkey1"
  public_key = tls_private_key.pkey.public_key_openssh
}


resource "aws_security_group" "allow_80" {
  name        = "allow_80"
  description = "Allow port 80"

  ingress {
    description = "incoming http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "incoming ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_80"
  }
}


resource "aws_instance" "WebServer" {
  ami           = "ami-005956c5f0f757d37"
  instance_type = "t2.micro"
  availability_zone = aws_ebs_volume.Volume.availability_zone
  key_name      = "webkey1"
  security_groups = ["${aws_security_group.allow_80.name}"]
  user_data = <<-EOF
                #! /bin/bash
                sudo su - root
                sudo yum install httpd -y
                sudo yum install php -y
                sudo systemctl start httpd
                sudo systemctl enable httpd
                sudo yum install git -y
                sudo setenforce 0
                EOF

  tags = {
    Name = "WebOS"
  }
}


resource "aws_ebs_volume" "Volume" {
  availability_zone = "ap-south-1a"
  size              = 1
  
  tags = {
    Name = "web_volume"
  }
}


resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdr"
  volume_id   = aws_ebs_volume.Volume.id
  instance_id = aws_instance.WebServer.id
  force_detach = true
}


resource "null_resource" "remote"  {
  depends_on = [
    aws_volume_attachment.ebs_att,
  ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.pkey.private_key_pem
    host     = aws_instance.WebServer.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdr",
      "sudo mount  /dev/xvdr  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/sahushoumik23/CloudTask1.git /var/www/html/"
    ]
  }
}



resource "aws_s3_bucket" "s3bucket" {
  acl = "private"
  
  tags = {
    Name = "s3bucket"
  }
}


resource "aws_s3_bucket_public_access_block" "s3type" {
  bucket = "${aws_s3_bucket.s3bucket.id}"
  block_public_acls   = true
  block_public_policy = true
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  depends_on = [aws_s3_bucket.s3bucket]
}



locals {
  s3_origin_id = "myS3Origin"
}




resource "aws_cloudfront_distribution" "webcloud" {
  origin {
    domain_name = "${aws_s3_bucket.s3bucket.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"
    s3_origin_config{
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }

  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "null_resource" "wepip"  {
	provisioner "local-exec" {
	    command = "echo  ${aws_instance.WebServer.public_ip} > publicip.txt"
  	}
}
