# 🔐 Sealed Secrets Setup Guide

Complete step-by-step guide to using **Bitnami Sealed Secrets** for secure,
GitOps-compatible secret management with this Helm chart.

---

## Why Sealed Secrets?

| Feature | Plain Secrets | Sealed Secrets | External Secrets (ESO) |
|---------|--------------|----------------|----------------------|
| Git-safe | ❌ Never | ✅ Yes | ✅ Yes |
| Cloud dependency | ❌ None | ❌ None | ✅ Needs AWS/Vault/GCP |
| Works offline | ✅ Yes | ✅ Yes | ❌ No |
| Cluster-scoped encryption | — | ✅ RSA 4096 | — |
| Best for | Dev only | GitOps prod | Cloud-native prod |

---

## Prerequisites

- `kubectl` configured and connected to your cluster
- `helm` 3.0+
- `kubeseal` CLI installed locally

### Install `kubeseal` CLI

```bash
# macOS
brew install kubeseal

# Linux (amd64)
KUBESEAL_VERSION="0.27.0"
curl -OL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
tar -xvzf "kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz" kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# Windows (PowerShell) - download from GitHub releases
# https://github.com/bitnami-labs/sealed-secrets/releases
```

---

## Step 1: Install Sealed Secrets Controller

Install the controller into `kube-system` namespace (required — this is where
the decryption key lives and where the controller watches for SealedSecret resources).

```bash
# Add the Bitnami sealed-secrets Helm repository
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update

# Install the controller in kube-system
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --set fullnameOverride=sealed-secrets-controller

# Verify the controller is running
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets
kubectl get crd sealedsecrets.bitnami.com
```

Expected output:
```
NAME                              READY   STATUS    RESTARTS   AGE
sealed-secrets-controller-xxxx   1/1     Running   0          30s
```

---

## Step 2: Fetch the Public Certificate

The controller generates an RSA key pair on first run. Fetch the public cert for
encrypting secrets locally.

```bash
# Fetch and save the public certificate
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  > pub-sealed-secrets.pem

# Verify the cert was fetched
cat pub-sealed-secrets.pem
```

> **Store this cert in your repo** — it's safe to commit and needed to encrypt secrets offline.

---

## Step 3: Create a Plain Kubernetes Secret (Local Only — Never Commit)

Create a temporary plain secret file. **This file must NOT be committed to Git.**

```bash
# Create a temporary plain secret manifest
cat > /tmp/leave-system-plain-secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: release-name-leave-management-system-secrets
  namespace: production
type: Opaque
stringData:
  db-user: prod_db_user
  db-password: YourStrongPassword123!
  jwt-secret: YourVeryLongJWTSecretKeyMinimum32Chars!!
  root-password: YourStrongRootPassword123!
  db-host: release-name-leave-management-system-mysql
  db-name: leave_db
EOF
```

> ⚠️ **Adjust the `name` and `namespace`** to match your Helm release name and namespace.
> The Secret name format is: `<release-name>-leave-management-system-secrets`

---

## Step 4: Encrypt with kubeseal

```bash
# Encrypt the secret using the controller in kube-system
kubeseal \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  --format=yaml \
  < /tmp/leave-system-plain-secret.yaml \
  > /tmp/leave-system-sealed.yaml

# View the sealed output
cat /tmp/leave-system-sealed.yaml
```

The output looks like:
```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: release-name-leave-management-system-secrets
  namespace: production
spec:
  encryptedData:
    db-user: AgB...long-base64-string...
    db-password: AgB...long-base64-string...
    jwt-secret: AgB...long-base64-string...
    root-password: AgB...long-base64-string...
    db-host: AgB...long-base64-string...
    db-name: AgB...long-base64-string...
  template:
    metadata:
      name: release-name-leave-management-system-secrets
      namespace: production
    type: Opaque
```

---

## Step 5: Update `values-prod.yaml`

Copy the `encryptedData` values from the kubeseal output into `values-prod.yaml`:

```yaml
# helm-chart/values-prod.yaml
backend:
  secrets:
    externalSecrets: false
    sealedSecrets: true
    sealedSecretsData:
      db-user: AgB...           # paste your kubeseal encrypted value
      db-password: AgB...       # paste your kubeseal encrypted value
      jwt-secret: AgB...        # paste your kubeseal encrypted value
      root-password: AgB...     # paste your kubeseal encrypted value
      db-host: AgB...           # paste your kubeseal encrypted value
      db-name: AgB...           # paste your kubeseal encrypted value
```

✅ **This file is now safe to commit to Git.**

---

## Step 6: Deploy with Helm

```bash
# Install (first time)
helm install leave-system ./helm-chart \
  -f helm-chart/values.yaml \
  -f helm-chart/values-prod.yaml \
  -n production \
  --create-namespace

# Verify the SealedSecret was created and decrypted
kubectl get sealedsecret -n production
kubectl get secret release-name-leave-management-system-secrets -n production

# If decryption was successful you'll see the plain Secret was created:
kubectl get secret -n production | grep leave-management
```

---

## Step 7: Verify Decryption

```bash
# Check SealedSecret status (should show "True" for Ready condition)
kubectl describe sealedsecret -n production release-name-leave-management-system-secrets

# Check controller logs for any decryption errors
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets -f

# Verify the resulting plain Secret exists (controller creates it automatically)
kubectl get secret release-name-leave-management-system-secrets -n production -o yaml
```

---

## Upgrading Sealed Secrets Controller

```bash
helm upgrade sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --set fullnameOverride=sealed-secrets-controller
```

---

## Key Rotation

If you need to rotate the encryption key:

```bash
# The controller auto-rotates keys every 30 days by default
# Old keys are kept for decryption of existing SealedSecrets

# Manual key rotation
kubectl rollout restart deployment sealed-secrets-controller -n kube-system

# After rotation, re-fetch the public cert and re-encrypt all secrets
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  > pub-sealed-secrets.pem
```

---

## Offline Encryption (CI/CD)

For encrypting secrets in CI/CD without a live cluster, use the saved public cert:

```bash
# In GitLab CI / GitHub Actions — use the saved pub cert
kubeseal \
  --cert pub-sealed-secrets.pem \
  --format=yaml \
  < plain-secret.yaml \
  > sealed-secret.yaml
```

---

## GitLab CI Integration

Add a job to auto-seal secrets (optional advanced pattern):

```yaml
# .gitlab-ci.yml
seal_secrets:
  stage: build
  image:
    name: alpine/k8s:1.28.3
    entrypoint: [""]
  script:
    - curl -OL https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.0/kubeseal-0.27.0-linux-amd64.tar.gz
    - tar -xzf kubeseal-*.tar.gz && mv kubeseal /usr/local/bin/
    - kubeseal --cert pub-sealed-secrets.pem --format=yaml < plain-secret.yaml > sealed-secret.yaml
  only:
    - main
```

---

## Troubleshooting

### SealedSecret not being decrypted

```bash
# Check controller is running
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets

# Check controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets

# Check SealedSecret events
kubectl describe sealedsecret -n production <name>
```

Common errors:
- `no key could decrypt secret` → The SealedSecret was encrypted with a different cluster's key
- `namespace mismatch` → Ensure the namespace in the sealed secret matches the deployment namespace
- Controller not in `kube-system` → Ensure `--controller-namespace=kube-system` flag is used

### Wrong namespace in sealed secret

SealedSecrets are **namespace-scoped by default** — a secret sealed for `production`
cannot be decrypted in `staging`. Re-encrypt with the correct namespace:

```bash
# Ensure metadata.namespace in plain-secret.yaml matches your target namespace
# before running kubeseal
```

---

## .gitignore Recommendations

Add these to your `.gitignore` to prevent accidental secret commits:

```gitignore
# Plain secrets - NEVER commit
*plain-secret*.yaml
*plain-secret*.json
values-secrets.yaml
secrets/
.env
.env.*
*.pem

# Temporary files
/tmp/
```

✅ `pub-sealed-secrets.pem` — **safe to commit**
✅ `values-prod.yaml` with `sealedSecretsData` — **safe to commit after kubeseal encryption**
❌ Plain `Secret` YAML files — **never commit**
