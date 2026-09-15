# Thin wrapper over the Lambda Cloud REST API — see README.md in this directory for why
# this isn't a native provider. `terraform destroy` is what actually stops billing.

terraform {
  required_version = ">= 1.5.0"
}

locals {
  nodes = ["node0", "node1"]
}

resource "null_resource" "gpu_node" {
  for_each = toset(local.nodes)

  triggers = {
    name          = "gpu-lab-${each.key}"
    instance_type = var.instance_type
    region        = var.region
    # Destroy-time provisioners may only reference self/count.index/each.key, never
    # var.* directly — stashing the API key here is the documented workaround.
    api_key       = var.lambda_api_key
  }

  provisioner "local-exec" {
    command = <<-EOT
      curl -sS -u "${var.lambda_api_key}:" -X POST \
        https://cloud.lambdalabs.com/api/v1/instance-operations/launch \
        -H 'Content-Type: application/json' \
        -d '{"region_name":"${var.region}","instance_type_name":"${var.instance_type}","ssh_key_names":["${var.ssh_key_name}"],"name":"gpu-lab-${each.key}"}' \
        -o ${path.module}/.launch_${each.key}.json
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      id=$(jq -r '.data.instance_ids[0]' ${path.module}/.launch_${each.key}.json 2>/dev/null || echo "")
      if [ -n "$id" ]; then
        curl -sS -u "${self.triggers.api_key}:" -X POST \
          https://cloud.lambdalabs.com/api/v1/instance-operations/terminate \
          -H 'Content-Type: application/json' \
          -d "{\"instance_ids\":[\"$id\"]}"
      fi
    EOT
  }
}

output "note" {
  value = "Instance IDs/IPs land in .launch_node0.json / .launch_node1.json — poll instance status via lambda_cloud_api.sh list-instances, same as the non-Terraform path."
}
