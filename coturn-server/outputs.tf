output "nlb_url" {
  value = aws_lb.coturn_ingress_nlb.dns_name
}
