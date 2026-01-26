#! /bin/bash

set -e -o pipefail

SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
cd "$SCRIPT_DIR"

# Auto-detect if terraform init is needed (first-time run or missing lock file)
if [[ ! -d ".terraform" ]] || [[ ! -f ".terraform.lock.hcl" ]]; then
  echo "Terraform not initialized. Running terraform init..."
  terraform init
fi

terraform destroy --auto-approve
