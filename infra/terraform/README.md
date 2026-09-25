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

This is a wrapper, not a native provider. It gets the job done for a PoC, but a
first-party Terraform provider would be a real improvement for customers who
standardize on Terraform. It's the kind of product gap worth feeding back to the
provider.
