# Agentic Ops Guardrails

Sample Kyverno policies from the talk **"Agentic Ops: Building Guardrails for Autonomous AI with Policy-as-Code"**
by Pavan Madduri, KyvernoCon at KubeCon + CloudNativeCon North America 2026, Salt Lake City.

The idea: an AI agent is non-deterministic, so the safety boundary has to live outside the model.
Kubernetes admission control is deterministic, applies to every identity equally, and cannot be
prompt-injected. These three `ValidatingPolicy` resources put that boundary around an agent that
runs as the ServiceAccount `system:serviceaccount:agent-ops:remediation-agent`.

| Pattern | Policy | What it does |
|---|---|---|
| 1. Allowlist | [`agent-scale-bounds`](policies/agent-scale-bounds.yaml) | The agent may only scale Deployments to 1–10 replicas, and only in namespaces labeled `agent-ops/managed: "true"`. Humans are not matched. |
| 2. Hard denies | [`agent-hard-denies`](policies/agent-hard-denies.yaml) | Any `agent-ops` ServiceAccount is denied CREATE/UPDATE/DELETE on PVCs, Namespaces, StatefulSets, RBAC, NetworkPolicy, and Kyverno's own policies and exceptions. The guardrails guard themselves. |
| 3. Human approval | [`agent-requires-human-approval`](policies/agent-requires-human-approval.yaml) | Tier-2 changes (ConfigMaps, Deployment template changes) must carry an `ops.example.com/approved-by` annotation whose value is not the agent's own identity. The agent cannot self-approve. |

Every policy matches on `request.userInfo.username`, so the constraints apply to the agent identity only.

## Run the tests

Requires the [Kyverno CLI](https://kyverno.io/docs/kyverno-cli/) (tested with 1.17.2 against the `policies.kyverno.io/v1` API).

```bash
kyverno test tests   # or: make test
```

Or apply a single policy by hand, acting as the agent:

```bash
kyverno apply policies/agent-scale-bounds.yaml \
  --resource tests/resources/deployments.yaml \
  --userinfo tests/user-info-agent.yaml \
  --context-file tests/context.yaml
```

`tests/user-info-agent.yaml` supplies the agent's ServiceAccount identity and `tests/context.yaml`
supplies the `shop` (managed) and `finance` (unmanaged) namespaces so `namespaceObject` resolves.

Expected results:

| Resource | Policy | Result |
|---|---|---|
| `shop/checkout-scale-5` | agent-scale-bounds | pass |
| `shop/checkout-scale-0` | agent-scale-bounds | fail: replicas must be 1-10 |
| `finance/payments-scale-5` | agent-scale-bounds | fail: namespace not agent-managed |
| `shop/checkout-data` (PVC) | agent-hard-denies | fail |
| `shop/agent-wider-access` (RoleBinding) | agent-hard-denies | fail |
| `shop/checkout-config-approved` | agent-requires-human-approval | pass |
| `shop/checkout-config-unapproved` | agent-requires-human-approval | fail |
| `shop/checkout-config-self-approved` | agent-requires-human-approval | fail |

## Install in a cluster

```bash
kubectl apply -f policies/
```

Requires Kyverno 1.14 or later (CEL `ValidatingPolicy`). Pair the policies with a least-privilege
RBAC Role for the agent's ServiceAccount; the policies constrain what an already-authorized request
may do, they do not grant anything.

## Notes and limits

- The Deployment rule in `agent-requires-human-approval` compares `oldObject.spec.template` with the
  new one, so it only triggers on UPDATE in a live cluster. The CLI tests exercise the ConfigMap path.
- The replica bound does not stop the agent from changing other Deployment fields in the same request.
  Add an `oldObject` comparison if you want a strict replicas-only contract.
- On a GitOps path, admission sees the GitOps controller's identity, not the agent's. Bind the agent to
  a protected repository path and run the same policies in CI with `kyverno test` so the boundary holds
  before the controller ever submits the change.
- Break-glass is a time-boxed `PolicyException`, reviewed in Git like everything else.

## Further reading

- Pavan Madduri, ["Agentic AIOps: How to Build the Guardrails for Autonomous Infrastructure"](https://www.vktr.com/ai-technology/agentic-aiops-building-the-guardrails-for-autonomous-infrastructure/), VKTR, May 2026. The longer-form argument behind this talk: GitOps first, shadow mode, least privilege, then policy-as-code admission control.
- [Kyverno ValidatingPolicy docs](https://kyverno.io/docs/policy-types/validating-policy/)
- [Kyverno CLI: test](https://kyverno.io/docs/kyverno-cli/usage/test/)

## License

Apache-2.0
