variable "region" {
  default = "us-east-1"
}

variable "ami_id" {
  default = "ami-01e3c4a339a264cc9"  # Example Amazon Linux AMI, change as needed
}

variable "instance_type" {
  default = "t2.micro"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "subnet_cidr" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

####

