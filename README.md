## References
1. WebRTC example play-from-disk: https://github.com/pion/webrtc/tree/master/examples/play-from-disk
2. Coturn open-source TURN server Docker setup guide: https://github.com/coturn/coturn/tree/master
   * coturn Debian/ARM64 image: https://hub.docker.com/layers/coturn/coturn/edge-debian-arm64v8/images/sha256-46d5d580d10f2bbf7d317dae816d06c4d26a6daaef796c221a0c915acd602b6c?context=explore
   * alternative to coturn - OpenRelay: https://www.metered.ca/tools/openrelay/
3. ECS cluster with Terraform setup guide:
    * Basic setup guidhttps://spacelift.io/blog/terraform-ecs
    * Dedicated EC2 setup guide: https://medium.com/@vladkens/aws-ecs-cluster-on-ec2-with-terraform-2023-fdb9f6b7db07
    * cidr subset function: https://developer.hashicorp.com/terraform/language/functions/cidrsubnet
    * ECS Task Definition bind mounts: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/specify-bind-mount-config.html
4. 