group "default" {
  targets = [
    "runtime",
  ]
}
group "local" {
  targets = ["local-amd64-proxy", "local-arm64-proxy"]
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
target "local" {
  inherits = ["builds"]
 matrix = {
    i = [{ tgt = "proxy", img = "proxy" }],
    p = [
      { platform = "linux/amd64", suffix = "amd64" },
      { platform = "linux/arm64", suffix = "arm64" },
    ],
  }

  target     = "${i.tgt}"
  name       = "local-${p.suffix}-${i.img}"
  output     = ["type=image,load=true"]
  cache-to   = ["/tmp/build-cache/${i.img}", "mode=min,if-exists=false"]
  cache-from = []
  attest     = []
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
  name   = "builds-${i.img}-${p.suffix}"
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
