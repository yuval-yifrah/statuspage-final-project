# statuspage-final-project

## Secrets Management for Statuspage Helm Chart

To keep sensitive data (like database credentials) safe, we do **not** store them in the `values.yaml` file or in GitHub.  
Instead, we manage them using a Kubernetes **Secret** created from a local file.

---

### 1. Create the `my-secrets.yaml` file

Create a local file named `my-secrets.yaml` (this file is ignored by `.gitignore` and must never be pushed to Git):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: statuspage-chart-secrets
type: Opaque
stringData:
  DATABASE_USER: "<your-database-user>"
  DATABASE_PASSWORD: "<your-database-password>"  

Replace <your-database-user> and <your-database-password> with your actual credentials.

### 2. apply the secret to k8s

kubectl apply -f my-secrets.yaml

verify the secrets:  
kubectl get secrets

### 3. deploy helm:  
helm upgrade --install statuspage ./helm -n <namespace>

