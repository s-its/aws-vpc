# AWS VPC terraform module
Terraform module which creates VPC resources on AWS.

## Usage

```hcl
module "vpc" {
  source = "git::https://github.com/s-its/aws-vpc.git?ref=v1.0.1"
  name = "my-vpc"
  ipv4_cidr = "10.0.0.0/16"

  azs             = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true

  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}
```
