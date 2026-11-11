# Recipes for terraform-vantage-agents. Run `just` to list them.

default:
    @just --list

# Format check, validate and shellcheck.
lint:
    terraform fmt -check -recursive
    terraform init -backend=false -input=false >/dev/null
    terraform validate
    shellcheck scripts/*.sh tests/*.sh

# Apply the module twice against a throwaway Ubuntu 26.04 VM and check that the
# second apply changes nothing. The VM must be disposable: the test installs
# stub services and a stub artifact server. It proves the module's logic only;
# real verification needs a VM from the Vantage image and a real cluster.
# Usage: just test <user> <host> <port> <private-key-file>
test user host port key:
    scp -P {{port}} -i {{key}} -o StrictHostKeyChecking=accept-new tests/stub_cdn.py tests/prepare.sh {{user}}@{{host}}:
    ssh -p {{port}} -i {{key}} {{user}}@{{host}} 'sudo bash prepare.sh'
    cd tests && terraform init -input=false >/dev/null
    cd tests && TF_VAR_host={{host}} TF_VAR_ssh_port={{port}} TF_VAR_ssh_user={{user}} TF_VAR_ssh_private_key="$(cat {{key}})" terraform apply -auto-approve -input=false
    cd tests && TF_VAR_host={{host}} TF_VAR_ssh_port={{port}} TF_VAR_ssh_user={{user}} TF_VAR_ssh_private_key="$(cat {{key}})" terraform plan -detailed-exitcode -input=false
    ssh -p {{port}} -i {{key}} {{user}}@{{host}} 'sudo bash -s' < tests/verify.sh
