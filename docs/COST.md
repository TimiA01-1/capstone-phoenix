# Cost — Phoenix (TaskApp on k3s)

## Monthly cost breakdown (eu-west-2, on-demand pricing)

| Item | Qty | Unit cost | Monthly |
|---|---|---|---|
| EC2 t3.small (control-plane) | 1 | ~$0.0216/hr | ~$15.77 |
| EC2 t3.small (workers) | 2 | ~$0.0216/hr | ~$31.54 |
| EBS gp3 root volumes (8GB default) | 3 | ~$0.088/GB-mo | ~$2.11 |
| S3 (Terraform state, tiny) | 1 bucket | negligible | ~$0.02 |
| DynamoDB (lock table, on-demand) | 1 table | negligible | ~$0.01 |
| Data transfer out (light usage) | - | ~$0.09/GB | ~$1-3 |
| Route53 / domain | 0 | using free nip.io | $0.00 |
| TLS certificates | 0 | Let's Encrypt, free | $0.00 |

**Estimated total: ~$50-55/month** while the cluster runs continuously.

## How I'd cut this in half

The single biggest lever is instance uptime, not instance size: this is a lab/demo
workload with no real traffic, so the 3 EC2 instances running 24/7 account for
~90% of the cost regardless of how small they are. Stopping (not terminating) all 3
instances outside of active development/demo windows - e.g. via a scheduled Lambda
or just manually before/after each work session - would cut EC2 cost roughly in
proportion to the hours actually used; realistically 6-8 active hours/day instead of
24 brings the ~$47 EC2 line down to roughly $12-16/month, taking the total to
around $15-20/month. A further step for a real always-on production workload would
be committing to a 1-year Savings Plan (~30-40% off on-demand) once traffic patterns
are known, or moving to a single larger control-plane + smaller/fewer workers if the
actual load doesn't need 3 full nodes.
