# Terraform

Lambda Cloud has no first-party Terraform provider as of this writing, so `main.tf`
here is a thin `null_resource` + `local-exec` wrapper around the same REST calls
`../lambda_cloud_api.sh` makes directly. This is what both the GitHub Actions pipeline
(`.github/workflows/gpu-lab.yml`) and manual use call for provisioning — `../launch_cluster.sh`
still exists as a simpler, non-Terraform path if you just want to debug node access
without touching CI.

```bash
export TF_VAR_lambda_api_key=$LAMBDA_API_KEY
export TF_VAR_ssh_key_name=your-ssh-key-name
terraform init
terraform apply
terraform destroy   # when done — this is the part that actually stops billing
```

Be honest in the interview that this is a wrapper, not a native provider — that's a
more credible answer than pretending Lambda has first-class Terraform support today,
and it's a fine thing to raise as a product gap ("customer feedback & product advocacy"
is literally in the JD).
