variable "task_cpu" {
  type = number
  default = 256
}

variable "task_memory" {
  type = number
  default = 256
}

variable "coturn_image_tag" {
  type = string
  default = "edge-debian-arm64v8" # https://hub.docker.com/layers/coturn/coturn/edge-debian-arm64v8/images/sha256-46d5d580d10f2bbf7d317dae816d06c4d26a6daaef796c221a0c915acd602b6c?context=explore
}