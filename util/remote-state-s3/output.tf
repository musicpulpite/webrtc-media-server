output "remote-state-bucket-name" {
  value = aws_s3_bucket.terraform_state.id 
}

output "dynamodb-table-name" {
  value = aws_dynamodb_table.terraform_locks.name
}

