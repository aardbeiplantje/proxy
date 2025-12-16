group "default" {
  targets = [
    "runtime",
  ]
}
group "runtime" {
    targets = [
        "builds-proxy-amd64",
    ]
}
variable "DOCKER_TAG" {
  default = "latest"
}
variable "DOCKER_REPOSITORY" {
  default = "local/proxy"
}
target "builds" {
  pull = true
  progress = ["plain", "tty"]
  tags = [
    "${DOCKER_REPOSITORY}/${i.img}:${DOCKER_TAG}",
  ]
  matrix = {
    i = [
      {
        tgt = "proxy",
        img = "proxy",
      }
    ],
    p = [
      {
        platform = "linux/amd64",
        suffix = "amd64",
      },
      {
        platform = "linux/arm64",
        suffix = "arm64",
      },
    ],
  }
  target = "${i.tgt}"
  name = "builds-${i.img}-${p.suffix}"
  output = [
    "type=image,name=${DOCKER_REPOSITORY}/${i.img}:${DOCKER_TAG},push=true",
  ]
  cache-to = [
    "type=registry,ref=${DOCKER_REPOSITORY}/${i.img}:buildcache,mode=max",
  ]
  cache-from = [
    "type=registry,ref=${DOCKER_REPOSITORY}/${i.img}:buildcache",
    "type=registry,ref=${DOCKER_REPOSITORY}/${i.img}:${DOCKER_TAG}"
  ]
  attest = [
    "type=provenance,mode=max",
    "type=sbom",
  ]
  buildkit = true
  context = "."
  dockerfile = "Dockerfile"
  networks = ["host"]
  platforms = [p.platform]
}
