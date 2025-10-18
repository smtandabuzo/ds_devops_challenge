# Generate a new RSA key pair
resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create an AWS key pair
resource "aws_key_pair" "ec2_key_pair" {
  key_name   = "ds-devops-ec2-key"
  public_key = tls_private_key.ec2_key.public_key_openssh

  tags = {
    Name = "ds-devops-ec2-key"
  }
}

# Save the private key to a file
resource "local_file" "private_key" {
  content         = tls_private_key.ec2_key.private_key_openssh
  filename        = "${path.module}/ds-devops-ec2-key.pem"
  file_permission = "0400"
}

# Output the private key (for reference, handle with care)
output "private_key" {
  value       = tls_private_key.ec2_key.private_key_openssh
  sensitive   = true
  description = "SSH private key for EC2 instances (sensitive)"
}

output "key_name" {
  value       = aws_key_pair.ec2_key_pair.key_name
  description = "Name of the SSH key pair"
}
