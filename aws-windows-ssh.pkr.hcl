packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

variable "ami_name_prefix" {
  type    = string
  default = "windows-base-2022"
}

variable "image_name" {
  type    = string
  default = "Windows Server 2022 image with ssh"
}

locals { timestamp = regex_replace(timestamp(), "[- TZ:]", "") }

data "amazon-ami" "aws-windows-ssh" {
  filters = {
    name                = "Windows_Server-2022-English-Full-Base-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
}

source "amazon-ebs" "aws-windows-ssh" {
  source_ami                  = "${data.amazon-ami.aws-windows-ssh.id}"
  ami_name                    = "${var.ami_name_prefix}-${local.timestamp}"
  ami_description             = "${var.image_name}"
  ami_virtualization_type     = "hvm"
  associate_public_ip_address = true
  communicator                = "ssh"
  spot_price                  = "auto"
  spot_instance_types         = ["c7i.xlarge", "c7a.xlarge", "c6i.xlarge", "c6a.xlarge", "c5a.xlarge", "m6a.xlarge", "m5a.xlarge", "m5.xlarge"]
  ssh_timeout                 = "10m"
  ssh_username                = "Administrator"
  ssh_file_transfer_method    = "sftp"
  user_data_file              = "files/configure-source-ssh.ps1"
  fast_launch {
    enable_fast_launch = false
  }
  snapshot_tags = {
    Name      = "${var.image_name}"
    BuildTime = "${local.timestamp}"
  }

  tags = {
    Name      = "${var.image_name}"
    BuildTime = "${local.timestamp}"
  }
}

build {
  sources = ["source.amazon-ebs.aws-windows-ssh"]

  provisioner "powershell" {
    script = "files/install-choco.ps1"
  }

  provisioner "powershell" {
    script = "files/prepare-image.ps1"
  }
}
