# frozen_string_literal: true

namespace :terraform do
  namespace :staging do
    desc 'Setup terraform for default staging env'
    task init: :environment do
      puts 'Enter your AWS named profile:'
      aws_profile = STDIN.gets.chomp
      AWS_ACCESS_KEY_ID = `aws --profile #{aws_profile} configure get aws_access_key_id`.chomp
      if AWS_ACCESS_KEY_ID.blank?
        abort('Please check your AWS named profile in ~/.aws/credentials file')
      end
      AWS_SECRET_ACCESS_KEY = `aws --profile #{aws_profile} configure get aws_secret_access_key`.chomp
      if AWS_SECRET_ACCESS_KEY.blank?
        abort('Please check your AWS named profile in ~/.aws/credentials file')
      end

      puts "AWS_ACCESS_KEY_ID is #{AWS_ACCESS_KEY_ID}"
      puts "AWS_SECRET_ACCESS_KEY is #{AWS_SECRET_ACCESS_KEY}"

      REGION = 'us-east-1'
      PRIVATE_KEY_FILE_NAME = "#{Rails.application.class.module_parent_name}-staging"

      puts "AWS REGION used is #{REGION}"

      if File.exist? "#{Rails.root.join('terraform', 'staging')}/#{PRIVATE_KEY_FILE_NAME}"
        puts 'Private key already created'
      else
        puts 'Create private key file for staging'
        sh "ssh-keygen -t rsa -f #{Rails.root.join('terraform', 'staging')}/#{PRIVATE_KEY_FILE_NAME} -C #{PRIVATE_KEY_FILE_NAME}"
      end

      puts 'Create setup.tf file for staging'
      file = File.open(Rails.root.join('terraform', 'staging', 'setup.tf'), 'w')
      file.puts <<~MSG
        # download all necessary plugins for terraform
        # set versions
        terraform {
          required_version = "~> 0.12.0"
        }

        provider "aws" {
          version = "~> 2.24"
          region = "us-east-1"
        }

        provider "null" {
          version = "~> 2.1"
        }
      MSG
      file.close

      puts 'Create variables.tf file for staging'
      file = File.open(Rails.root.join('terraform', 'staging', 'variables.tf'), 'w')
      file.puts <<~MSG
        variable "project_name" {
          type = string
          default = "#{Rails.application.class.module_parent_name.downcase}"
        }

        variable "region" {
          type = string
          default = "#{REGION}"
        }

        variable "env" {
          type = string
          default = "staging"
        }
      MSG
      file.close

      puts 'Create secrets_bucket.tf file for staging to upload private and public keys'
      file = File.open(Rails.root.join('terraform', 'staging', 'secrets_bucket.tf'), 'w')
      file.puts <<~MSG
        module "secrets_bucket" {
          source = "trussworks/s3-private-bucket/aws"
          version = "~> 1.7.2"
          bucket = "${var.project_name}-secrets-bucket"
          logging_bucket = aws_s3_bucket.secrets_log_bucket.id

          tags = {
            Name = var.project_name
            Env = var.env
          }
        }

        resource "aws_s3_bucket" "secrets_log_bucket" {
          bucket = "${var.project_name}-secrets-log-bucket"
          acl = "log-delivery-write"

          tags = {
            Name = var.project_name
            Env = var.env
          }
        }

        resource "aws_s3_bucket_object" "private_key" {
          bucket = module.secrets_bucket.id
          key = "ssh_keys/#{PRIVATE_KEY_FILE_NAME}"
          source = "#{PRIVATE_KEY_FILE_NAME}"
        }

        resource "aws_s3_bucket_object" "public_key" {
          bucket = module.secrets_bucket.id
          key = "ssh_keys/#{PRIVATE_KEY_FILE_NAME}.pub"
          source = "#{PRIVATE_KEY_FILE_NAME}.pub"
        }

        # with reference to https://stackoverflow.com/a/52868251/2667545

        data "aws_iam_policy_document" "secrets_bucket" {
          statement {
            actions = ["sts:AssumeRole"]

            principals {
              type        = "Service"
              identifiers = ["ec2.amazonaws.com"]
            }
          }
        }

        resource "aws_iam_policy" "secrets_bucket" {
          name = "${module.secrets_bucket.id}-secrets_bucket_iam_policy"
          description = "Allow reading from the S3 bucket"

          policy = <<EOF
        {
          "Version":"2012-10-17",
          "Statement":[
            {
              "Effect":"Allow",
              "Action":[
                "s3:GetObject"
              ],
              "Resource":[
                "${module.secrets_bucket.arn}",
                "${module.secrets_bucket.arn}/*"
              ]
            },
            {
              "Effect":"Allow",
              "Action":[
                "s3:ListAllMyBuckets"
              ],
              "Resource":"*"
            }
          ]
        }
        EOF
        }

        resource "aws_iam_role" "secrets_bucket" {
          name = "${module.secrets_bucket.id}-iam_role"
          assume_role_policy = data.aws_iam_policy_document.secrets_bucket.json
        }

        resource "aws_iam_role_policy_attachment" "secrets_bucket" {
          role = aws_iam_role.secrets_bucket.name
          policy_arn = aws_iam_policy.secrets_bucket.arn
        }

        resource "aws_iam_instance_profile" "secrets_bucket" {
          name = "${module.secrets_bucket.id}-iam_instance_profile"
          role = aws_iam_role.secrets_bucket.name
        }
      MSG
      file.close

      puts 'Create ec2.tf file for staging'
      file = File.open(Rails.root.join('terraform', 'staging', 'ec2.tf'), 'w')
      file.puts <<~MSG
        resource "aws_key_pair" "this" {
          key_name   = var.project_name
          public_key = file("${path.module}/#{PRIVATE_KEY_FILE_NAME}.pub")
        }

        resource "aws_security_group" "this" {
          name = var.project_name
          description = "Security group for ${var.project_name} project"
          ingress {
            from_port = 80
            to_port = 80
            protocol = "tcp"
            cidr_blocks = [
              "0.0.0.0/0"
            ]
          }

          ingress {
            from_port = 22
            to_port = 22
            protocol = "tcp"
            cidr_blocks = [
              "0.0.0.0/0"
            ]
          }

          egress {
            from_port = 0
            to_port = 0
            protocol = "-1"
            cidr_blocks = [
              "0.0.0.0/0"
            ]
          }

          tags = {
            Name = var.project_name
            Env = var.env
          }
        }

        resource "aws_eip" "this" {
          vpc = true
          tags = {
            Name = var.project_name
            Env = var.env
          }

          # needs to persist?
          # lifecycle {
          #   prevent_destroy = true
          # }
        }

        resource "aws_eip_association" "this" {
          instance_id   = "${aws_instance.this.id}"
          allocation_id = "${aws_eip.this.id}"
        }

        resource "aws_instance" "this" {
          ami = "ami-035b3c7efe6d061d5" # Amazon Linux 2018
          instance_type = "t2.nano"
          availability_zone = "${var.region}a"
          key_name = aws_key_pair.this.key_name
          security_groups = [
            aws_security_group.this.name
          ]

          iam_instance_profile = aws_iam_instance_profile.secrets_bucket.name

          tags = {
            Name = var.project_name
            Env = var.env
          }
        }
      MSG
      file.close

      puts 'Create deploy.sh file for staging'

      ## deployment scripts ##

      # temporary; use terraform backend
      `touch #{Rails.root.join('terraform', 'staging', 'terraform.tfstate')}`

      file = File.open(Rails.root.join('terraform', 'staging', 'deploy.sh'), 'w')
      file.puts <<~MSG
        #!/usr/bin/env bash

        AWS_DEFAULT_REGION="#{REGION}"

        docker build -t #{Rails.application.class.module_parent_name.downcase}-staging:latest #{Rails.root.join('terraform', 'staging')}

        docker run \
          --rm \
          -it \
          -v #{Rails.root.join('terraform', 'staging')}/terraform.tfstate:/workspace/terraform.tfstate \
          --env AWS_ACCESS_KEY_ID=#{AWS_ACCESS_KEY_ID} \
          --env AWS_SECRET_ACCESS_KEY=#{AWS_SECRET_ACCESS_KEY} \
          #{Rails.application.class.module_parent_name.downcase}-staging \
          apply
      MSG
      file.close
      `chmod +x #{Rails.root.join('terraform', 'staging', 'deploy.sh')}`

      file = File.open(Rails.root.join('terraform', 'staging', 'destroy.sh'), 'w')
      file.puts <<~MSG
        #!/usr/bin/env bash

        AWS_DEFAULT_REGION="#{REGION}"

        docker run \
          --rm \
          -it \
          -v #{Rails.root.join('terraform', 'staging')}/terraform.tfstate:/workspace/terraform.tfstate \
          --env AWS_ACCESS_KEY_ID=#{AWS_ACCESS_KEY_ID} \
          --env AWS_SECRET_ACCESS_KEY=#{AWS_SECRET_ACCESS_KEY} \
          #{Rails.application.class.module_parent_name.downcase}-staging \
          destroy
      MSG
      file.close
      `chmod +x #{Rails.root.join('terraform', 'staging', 'destroy.sh')}`
    end

    desc 'Deply resources'
    task deploy: :environment do
      if File.exist? Rails.root.join('terraform', 'staging', 'deploy.sh')
        puts 'Initializing Terraform deploy script for staging environment'
        system(Rails.root.join('terraform', 'staging', 'deploy.sh').to_s)
      else
        abort("~/terraform/staging/deploy.sh script not present\nMake sure you run `rake terraform:staging:init`")
      end
    end

    desc 'Destroy resources'
    task destroy: :environment do
      if File.exist? Rails.root.join('terraform', 'staging', 'destroy.sh')
        puts 'Initializing Terraform destroy script for staging environment'
        system(Rails.root.join('terraform', 'staging', 'destroy.sh').to_s)
      else
        abort("~/terraform/staging/destroy.sh script not present\nMake sure you run `rake terraform:staging:init`")
      end
    end
  end
end
