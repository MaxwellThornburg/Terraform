provider "aws" {
  region = "us-west-2"
}

resource "aws_instance" "example" {
  ami           = "ami-0cc96c4cd98401dae"
  instance_type = "t2.micro"

  tags = {
    Name = "ExampleInstance"
  }
}