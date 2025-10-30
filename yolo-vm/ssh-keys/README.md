# SSH Public Keys

Place SSH public key files (`.pub`) in this directory. These keys will be
provisioned to the VM for both the default user and root.

## Usage

1. Copy your SSH public key file to this directory:
   `cp ~/.ssh/id_ed25519.pub ssh-keys/mykey.pub`

2. Run Terraform to provision the VM with updated keys:
   `terraform apply`

## Format

- Files must have `.pub` extension
- Standard SSH public key format (ssh-rsa, ssh-ed25519, etc.)
- One key per file
- Filenames are for organization only (not used in VM)

## Example

```text
ssh-keys/
├── alice.pub
├── bob.pub
└── ci-system.pub
```
