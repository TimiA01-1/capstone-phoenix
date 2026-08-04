## Architecture — Phoenix (TaskApp on k3s)

## Node topology

3 EC2 instances in eu-west-2, all in one VPC (10.0.0.0/16) / one public subnet (10.0.1.0/24):

| Role | Public IP | Private IP |
|---|---|---|
| control-plane (k3s server) | 18.169.158.77 | 10.0.1.90 |
| worker-1 (k3s agent) | 35.179.186.8 | 10.0.1.72 |
| worker-2 (k3s agent) | 18.135.28.92 | 10.0.1.12 |

A single k3s server is used (not multi-master) - per the brief, the difficulty here is
Kubernetes itself, not etcd quorum. Backend and frontend each run 2+ replicas spread
across the 2 worker nodes via topologySpreadConstraints, so a single node failure
never takes down 100% of either tier.

## Networking

- Firewall (AWS security group): only 22 (admin IP only), 80, 443 open to the
  internet. All other traffic (k3s API 6443, kubelet 10250, Flannel VXLAN 8472) is
  allowed only between the 3 nodes themselves, never publicly.
- In-node firewall: a second layer on top of the security group. Initially
  ufw's default-deny policy silently blocked node-to-node k3s traffic even though the
  AWS security group allowed it. It was fixed by adding a ufw rule allowing all traffic
  within the VPC CIDR (10.0.0.0/16), rather than trying to enumerate every k3s port.
- Ingress: k3s ships Traefik by default; used as it is rather than installing
  ingress-nginx on top, since Traefik was already running and healthy.
- CNI / NetworkPolicy: k3s's default CNI is Flannel, which does not enforce
  NetworkPolicy. It is Documented as a known limitation and was not implemented in this build;
  noted as a stretch item.

## Request flow

Browser --HTTPS--> Traefik (Ingress, TLS terminated here) --> frontend Service (nginx)
frontend nginx reverse-proxies /api/* --> backend Service:5000
backend (Flask) --> postgres Service (headless) --> postgres-0

Same-origin api was chosen over a separate api. subdomain: the frontend image's own
nginx config already reverse-proxies api to a Service named backend: this
was discovered by inspecting the image's baked in nginx config rather than assuming,
and it meant zero extra CORS configuration was needed.

## What each Core requirement fixes (the single-server assumption it replaces)

 | Requirement | Single-server assumption it breaks |
|---|---|

| 3-node cluster, spread constraints | "the app only needs to survive one machine" |
| Postgres StatefulSet + PVC | "the database's disk is always the same disk" (proven: deleted postgres-0, data survived via PVC reattachment) |
| 2+ replicas per tier | "one Flask process/one nginx process is enough" |
| Migration Job (not entrypoint) | with 2+ replicas, running alembic upgrade head in each replica's entrypoint races; moved to a one-shot Job that runs before replicas start |
| Probes (startup/readiness/liveness) | "if the process is running, it's healthy" |
| Ingress + real TLS | "one server, one static IP, no cert rotation to worry about" |
| GitOps (Argo CD) | replaces SSH-in-and-redeploy; git push is the only supported deploy path, selfHeal reverts manual drift automatically |
| HPA | "traffic is roughly constant" |
| PodDisruptionBudget | "taking a node down for maintenance never risks the whole tier" |

## Secrets & GitOps

The backend secret (DB password, SECRET_KEY) is never committed. A
secret.example.yaml template with placeholder CHANGEME values is committed for
documentation purposes. The real Secret is created via kubectl create
secret and Argo CD is explicitly configured to exclude *.example.yaml from its sync
(directory.exclude in gitops/taskapp-application.yaml) - discovered the hard way:
without the exclude, Argo CD's selfHeal repeatedly overwrote the real Secret with the
placeholder values from the example file.

## securityContext trade-offs

Backend:this runs as a genuine non root user baked into the image (appuser, uid 10001).
runAsNonRoot: true- requires a numeric UID to verify compliance - the image's USER
appuser directive alone wasn't enough, so runAsUser: 10001 is set explicitly. Full
hardening applied: dropped all capabilities, allowPrivilegeEscalation: false,
seccompProfile: RuntimeDefault.

Frontend:this runs the stock nginx base image, which genuinely runs as root and needs
CHOWN capability at startup to chown its own cache directory. runAsNonRoot and
capability-dropping were tried and it caused a real CrashLoopBackOff (chown failed:
Operation not permitted). Rather than force a broken hardening config, that was done: keep allowPrivilegeEscalation: false and seccompProfile:
RuntimeDefault (real, working hardening), but leave the container running as root,
since the base image wasn't built for non-root operation. A production fix would
rebuild the frontend image on an unprivileged nginx variant.

## Postgres storage limitation

Postgres uses k3s's default local-path StorageClass, which ties the PVC to whichever
node its data directory was first created on. It is acceptable for a single-replica
StatefulSet (Kubernetes reschedules postgres-0 back onto that same node), but does not
tolerate permanent loss of that specific node. A real HA Postgres setup (streaming
replication or managed RDS) would remove this constraint - noted as a stretch item.

## Incident: AMI auto-replacement (real production lesson)

Mid-build, all 3 EC2 instances were unexpectedly terminated and replaced by Terraform
during an unrelated apply (updating the SSH-allowed IP). Root cause: the compute
module used a data "aws_ami" "ubuntu" block with most_recent = true, which re resolves
to the latest Ubuntu 22.04 AMI on every apply. A new AMI had been published between
the original provisioning and this apply, so Terraform correctly determined the AMI had changed and replaced all 3 instances, wiping the cluster's
state (k3s, Postgres data, Argo CD).

Fix: the AMI is now pinned to a fixed ID via a variable with a hardcoded default,
rather than always resolving to "latest."

Recovery: because the entire application stack was already defined declaratively in
git (Terraform + Ansible + Kubernetes manifests, all Argo CD-managed), the cluster was
fully rebuilt - k3s reinstalled, Argo CD reinstalled, and the entire app redeployed
automatically by Argo CD from existing git state. 
