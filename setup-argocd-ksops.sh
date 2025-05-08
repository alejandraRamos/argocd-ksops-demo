#!/bin/bash

set -e

# 1. Iniciar Minikube
echo "🚀 Iniciando Minikube..."
minikube start --kubernetes-version=v1.27.0 -p demo-sops

# 2. Crear namespace de ArgoCD
echo "📦 Creando namespace 'argocd'..."
kubectl create namespace argocd || true

# 3. Instalar ArgoCD
echo "📥 Instalando ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Esperar que los pods estén listos
echo "⏳ Esperando a que ArgoCD esté listo..."
kubectl wait --for=condition=available --timeout=180s deployment/argocd-repo-server -n argocd

# 4. Parchear el repo-server para instalar KSOPS
echo "🛠️  Parcheando el argocd-repo-server para instalar KSOPS..."
echo "🛠️ Agregando el contenedor sidecar de KSOPS al repo-server..."
kubectl patch deployment argocd-repo-server -n argocd --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "cmp-tmp",
      "emptyDir": {}
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/-",
    "value": {
      "name": "ksops",
      "image": "viaductoss/ksops:v4.3.3",
      "command": ["/ksops"],
      "args": ["plugin"],
      "volumeMounts": [
        {
          "mountPath": "/tmp",
          "name": "cmp-tmp"
        }
      ]
    }
  }
]'

# 5. Agregar el plugin KSOPS en argocd-cm
echo "🔌 Configurando el plugin KSOPS en argocd-cm..."
kubectl patch configmap argocd-cm -n argocd --type merge -p '
data:
  configManagementPlugins: |
    - name: ksops
      init:
        command: [sh, -c, "echo init not required"]
      generate:
        command: [sh, -c, "ksops -r kustomize build ."]
'

# 6. Reiniciar el repo-server para aplicar cambios
echo "🔁 Reiniciando el argocd-repo-server..."
kubectl rollout restart deployment argocd-repo-server -n argocd

# 7. Exponer el ArgoCD UI
echo "🌐 Exponiendo ArgoCD UI en localhost:8080..."
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# 8. Mostrar password de acceso
echo "🔐 La contraseña de admin es:"
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
echo -e "\n\n✅ Todo listo. Accede a ArgoCD en: https://localhost:8080 (usuario: admin)"
