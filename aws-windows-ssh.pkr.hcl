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
  default = "Windows 2022 Image with ssh"
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
  ami_description             = "${var.image_name}"
  ami_name                    = "${var.ami_name_prefix}-${local.timestamp}"
  ami_virtualization_type     = "hvm"
  associate_public_ip_address = true
  communicator                = "ssh"
  instance_type               = "c5a.large"
  snapshot_tags = {
    Name = "${var.image_name}"
    OS   = "Windows-2022"
  }
  source_ami   = "${data.amazon-ami.aws-windows-ssh.id}"
  ssh_timeout  = "10m"
  ssh_username = "Administrator"
  tags = {
    Name = "${var.image_name}"
    OS   = "Windows-2022"
  }
  user_data_file = "files/configure-source-ssh.ps1"
}

build {
  sources = ["source.amazon-ebs.aws-windows-ssh"]

  provisioner "powershell" {
    inline = ["echo 'Provision Things Here' | Out-File C:/test.txt"]
  }

  provisioner "powershell" {
    script = "files/prepare-image.ps1"
  }

}
