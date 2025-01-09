output "elasticache_public_endpoint" {
  value = aws_elasticache_replication_group.main.primary_endpoint_address
}
