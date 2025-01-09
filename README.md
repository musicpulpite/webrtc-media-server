## Summary

The basic structure of this project is:

```
webrtc-media-server - root of project
├── coturn-server - open source TURN server deployed to AWS ECS (via Terraform)
│   ├── main.tf
│   ├── outputs.tf
│   ├── provider.tf
│   ├── turnserver.conf.tftpl
│   └── variables.tf
├── README.md
├── sdp-signalling-server - A Redis implmentation of a simple exchange of SDP offer/answers (AWS Elasticache via Terraform)
│   ├── main.tf
│   ├── outputs.tf
│   ├── provider.tf
│   ├── terraform.tfvars
│   └── variables.tf
├── server - Golang implemenation of a simple WebRTC server using pion/webrtc
│   ├── go.mod
│   ├── main.go
│   ├── message_handler.go
│   ├── ollama_wrapper.go
│   └── spd_signalling_server_controller.go
└── util - various necessary addons like the remote state that other terraform modules use
    └── remote-state-s3
        ├── main.tf
        ├── output.tf
        ├── provider.tf
        ├── terraform.tfstate
        └── terraform.tfstate.backup
```

## References

1. WebRTC example play-from-disk: https://github.com/pion/webrtc/tree/master/examples/play-from-disk
2. Coturn open-source TURN server Docker setup guide: https://github.com/coturn/coturn/tree/master
   - coturn Debian/ARM64 image: https://hub.docker.com/layers/coturn/coturn/edge-debian-arm64v8/images/sha256-46d5d580d10f2bbf7d317dae816d06c4d26a6daaef796c221a0c915acd602b6c?context=explore
   - alternative to coturn - OpenRelay: https://www.metered.ca/tools/openrelay/
3. ECS cluster with Terraform setup guide:
   - Basic setup guidhttps://spacelift.io/blog/terraform-ecs
   - Dedicated EC2 setup guide: https://medium.com/@vladkens/aws-ecs-cluster-on-ec2-with-terraform-2023-fdb9f6b7db07
   - cidr subset function: https://developer.hashicorp.com/terraform/language/functions/cidrsubnet
   - ECS Task Definition bind mounts: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/specify-bind-mount-config.html
4. A webrtc client I might use [99percentpeople/weblink](https://github.com/99percentpeople/weblink)
5. HTTP encapsulated over WebRTC with [ambianic/peerfetch](https://github.com/ambianic/peerfetch)
6. Private Home Surveillance with the WebRTC DataChannel (Ivelin Ivanov) [link](Private Home Surveillance with the WebRTC DataChannel (Ivelin Ivanov))
