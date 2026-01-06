#! /bin/bash

set -e -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Auto-detect if terraform init is needed (first-time run or missing lock file)
if [[ ! -d ".terraform" ]] || [[ ! -f ".terraform.lock.hcl" ]]; then
  echo "Terraform not initialized. Running terraform init..."
  terraform init
fi

terraform destroy --auto-approve
