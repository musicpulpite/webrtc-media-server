output "nlb_url" {
  value = aws_lb.coturn-ingress.dns_name
}