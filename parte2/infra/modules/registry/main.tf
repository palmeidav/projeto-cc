# Repositorios ECR na regiao do deploy + build/push das imagens a partir de services/.
# A tag e o hash do codigo-fonte: mudou o codigo -> nova imagem -> nova task definition.
data "aws_region" "current" {}
data "aws_caller_identity" "me" {}

locals {
  registry = "${data.aws_caller_identity.me.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com"
  src_hash = {
    for s, dir in var.services : s => substr(sha1(join("", [
      for f in sort(fileset(dir, "**")) : "${f}:${filesha1("${dir}/${f}")}"
      if !strcontains(f, "__pycache__") && !endswith(f, ".pyc")
    ])), 0, 12)
  }
}

resource "aws_ecr_repository" "this" {
  for_each             = var.services
  name                 = "${var.name}/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = var.force_delete
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "mantem as 10 imagens mais recentes"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}

resource "terraform_data" "image" {
  for_each         = var.services
  triggers_replace = [aws_ecr_repository.this[each.key].repository_url, local.src_hash[each.key]]
  input            = "${aws_ecr_repository.this[each.key].repository_url}:${local.src_hash[each.key]}"

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      # os 3 builds rodam em paralelo; o keychain do macOS falha se 2 logins gravam ao mesmo tempo -> tenta de novo
      for i in 1 2 3 4 5; do
        aws ecr get-login-password --region ${data.aws_region.current.region} \
          | docker login --username AWS --password-stdin ${local.registry} >/dev/null && break
        [ "$i" = 5 ] && exit 1
        sleep $((RANDOM % 5 + 2))
      done
      docker build --platform ${var.platform} -t ${aws_ecr_repository.this[each.key].repository_url}:${local.src_hash[each.key]} "${each.value}"
      docker push ${aws_ecr_repository.this[each.key].repository_url}:${local.src_hash[each.key]}
    EOT
  }
}
