# Runbook — Phoenix (TaskApp on k3s)

## 0. Prerequisites

- Terraform, Ansible, kubectl, AWS CLI installed locally
- AWS credentials configured under a named profile (this project uses `phoenix`)
- An SSH key pair generated at infra/terraform/phoenix-key (private, gitignored)
  and infra/terraform/phoenix-key.pub (public, committed)

## 1. Provision from zero

    cd infra/terraform-bootstrap
    terraform init
    terraform apply     # creates the S3 state bucket + DynamoDB lock table, once ever

    cd ../terraform
    cp terraform.tfvars.example terraform.tfvars
    # edit terraform.tfvars: set my_ip to `curl -s ifconfig.me`/32
    terraform init
    terraform plan       # sanity check: should show ~10 resources to add
    terraform apply      # creates VPC, subnet, security group, 3 EC2 instances

    terraform output     # note control_plane_public_ip, worker_public_ips

## 2. Cluster bring-up

    cd ../ansible
    cp phoenix-key... (copy the same private key used by terraform, or symlink it)
    # edit inventory.ini: set ansible_host values to the IPs from `terraform output`

    ansible -i inventory.ini all -m ping     # confirm all 3 hosts reachable
    ansible-playbook -i inventory.ini install-k3s.yml

    # fetch and fix up the kubeconfig
    scp -i phoenix-key ubuntu@<control-plane-ip>:/etc/rancher/k3s/k3s.yaml ./kubeconfig
    sed -i 's/127.0.0.1/<control-plane-public-ip>/' kubeconfig
    export KUBECONFIG=$(pwd)/kubeconfig
    kubectl get nodes    # all 3 should show Ready

## 3. Platform install (one-time, not GitOps-managed)

    # cert-manager
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml

    # Argo CD
    kubectl create namespace argocd
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

    # Traefik and metrics-server ship bundled with k3s, no action needed

## 4. App deploy (GitOps - do this once, then never kubectl apply the app manually again)

    kubectl create namespace taskapp
    kubectl create secret generic backend-secret \
      --from-literal=DATABASE_USER=taskapp_user \
      --from-literal=DATABASE_PASSWORD='<generate with: openssl rand -base64 24>' \
      --from-literal=SECRET_KEY='<generate with: openssl rand -base64 24>' \
      -n taskapp

    kubectl apply -f gitops/taskapp-application.yaml

    kubectl get application taskapp -n argocd   # wait for Synced + Healthy

Update docs/ingress.yaml's domain to match your control-plane's public IP
(taskapp.<ip>.nip.io), commit, push - Argo CD picks it up and cert-manager issues
a fresh Let's Encrypt cert automatically.

## 5. Scale

Edit replica counts in manifests/base/backend/deployment.yaml or frontend/deployment.yaml,
commit, push. Argo CD applies automatically (usually within ~3 min, or force it):

    kubectl patch application taskapp -n argocd --type merge \
      -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

The backend also autoscales on its own via HPA (2-6 replicas, 60% CPU target) -
no manual action needed under load.

## 6. Roll back

    git revert <bad-commit-sha>
    git push

Argo CD detects the revert commit and reconciles the cluster back to the previous
state automatically. Do not kubectl rollout undo directly - it would create drift
that selfHeal will immediately revert back to the (bad) git state.

## 7. Recover from a dead worker node

    kubectl get nodes                     # confirm which node is NotReady
    kubectl get pods -n taskapp -o wide    # confirm pods rescheduled to remaining nodes

If the node is truly gone (terminated, not just temporarily unreachable), remove it
from the cluster and provision a replacement:

    kubectl delete node <dead-node-name>
    # then re-run terraform apply + the relevant ansible-playbook agent role
    # against the new instance

## 8. Recover from a dead backend pod

Probes handle this automatically - a failed liveness probe triggers a restart, and
readiness probes pull an unhealthy pod out of the Service before users are affected.
To force-check:

    kubectl get pods -n taskapp -l app=backend
    kubectl logs <pod-name> -n taskapp
    kubectl describe pod <pod-name> -n taskapp   # check Events section for probe failures

## 9. Recover from a bad migration

The migration Job runs `alembic upgrade head` once, before replicas start. If it fails:

    kubectl logs -l job-name=backend-migrate -n taskapp
    kubectl delete job backend-migrate -n taskapp
    # fix the underlying issue (bad migration file, wrong DB state), then:
    kubectl apply -f manifests/base/backend/migration-job.yaml

If the database schema itself is in a bad state (e.g. mismatched alembic_version),
inspect and fix directly:

    kubectl exec -it postgres-0 -n taskapp -- psql -U taskapp_user -d taskapp \
      -c "SELECT * FROM alembic_version;"

## 10. Connecting to the cluster from a fresh laptop/session

kubectl needs port 6443 reachable. If SSH (port 22) is available:

    ssh -i infra/terraform/phoenix-key -L 6443:localhost:6443 ubuntu@<control-plane-ip> -N
    export KUBECONFIG=infra/ansible/kubeconfig   # server: should be 127.0.0.1:6443

If SSH is unavailable (e.g. carrier/firewall blocking port 22), use AWS EC2 Instance
Connect from the browser (AWS Console -> EC2 -> instance -> Connect -> EC2 Instance
Connect) and run `sudo kubectl ...` directly on the control-plane - no local kubectl
or tunnel needed at all, only outbound HTTPS to the AWS Console.

## 11. Known gotchas

- Your local public IP changes over time (especially on mobile/hotspot connections).
  If SSH or kubectl access suddenly stops working, check `curl -s ifconfig.me` against
  the security group's allowed IP first, before assuming something else broke.
- Never leave the SSH or 6443 security group rules open to 0.0.0.0/0 longer than
  needed for troubleshooting - always restrict back to your current IP afterward.
- The AMI is pinned in infra/terraform/modules/compute/variables.tf. Do not remove
  the pin (reverting to `data.aws_ami.ubuntu` "most recent") without understanding
  that it will cause Terraform to replace all 3 instances on the next apply if a
  newer AMI has been published since.
