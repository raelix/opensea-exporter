# Opensea Price Events 
This repositories contains the main configuration files to track 
floor price and events on Opensea. It is composed by two pieces:

- Argo workflow is mainly useful to generate notifications and rely completely on Kubernetes to scale as best as it can.
- Grafana, Prometheus and Alert Manager instead allows not just to monitor the prices but even the creation of alarms and trends.

## Pre-requisite
- Kubernetes > 1.20
- Helm 3

## Install Metallb & Ingress controller
```bash
helm upgrade --install --wait --timeout 15m \
  --namespace metallb-system --create-namespace \
  --repo https://metallb.github.io/metallb metallb metallb \
  --values - <<EOF
configInline:
  address-pools:
  - name: default
    protocol: layer2
    addresses:
    - 192.168.1.2-192.168.1.3
EOF 

# install ingress-nginx
helm upgrade --install --wait --timeout 15m \
  --namespace ingress-nginx --create-namespace \
  --repo https://kubernetes.github.io/ingress-nginx \
  ingress-nginx ingress-nginx \
  --values - <<EOF
defaultBackend:
  enabled: true
EOF

# retrieve local load balancer IP address
LB_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Bind the LB IP to the FQDN defined
```

## Install Cert-manager

```bash
helm upgrade cert-manager cert-manager/ --install --wait --timeout 15m   --namespace cert-manager --create-namespace -f cert-manager-values.yaml
kubectl apply -f staging-issuer.yaml -n cert-manager
kubectl apply -f prod-issuer.yaml -n cert-manager
```

## Install Keycloak
```bash
# helm repo add bitnami https://charts.bitnami.com/bitnami
# helm install keycloak bitnami/keycloak
kubectl create ns keycloack
helm install keycloak keycloak/ -f keycloack-values.yaml -n keycloack
```

## Run terraform on Keycloack
This procedure allow to configure keycloack to be used as OID connect server for Grafana 
```
cd terraform
terraform apply --auto-approve
```
> N.B. remember that the user must have the email configured otherwise the single sign-on will fail

## Installation Monitoring stack
The following commands will install:
- prometheus-operator
- grafana
- alert manager

```bash
# helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
# helm repo add stable https://charts.helm.sh/stable
# helm repo update
kubectl create ns monitoring
kubectl apply -f homeassistant-dashboard.yaml
kubectl apply -f opensea-dashboard.yaml
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring -f kube-prometheus-stack-values.yaml
helm install json-exporter prometheus-json-exporter/ -n monitoring -f prometheus-json-exporter-values.yaml  
# kubectl --namespace monitoring patch svc prometheus-grafana -p '{"spec": {"type": "NodePort"}}'
# kubectl --namespace monitoring patch svc prometheus-kube-prometheus-prometheus -p '{"spec": {"type": "NodePort"}}'
# kubectl --namespace monitoring patch svc prometheus-kube-prometheus-alertmanager -p '{"spec": {"type": "NodePort"}}'
```

The service patches are not required but useful for debug purposes.

### Install Prometheus JSON exporter
The provided ```prometheus-json-exporter-values.yaml``` contains already some customization related to my personal interests :) hence if you would like to monitor other projects please edit it.
```bash
helm install json-exporter prometheus-json-exporter/ -f prometheus-json-exporter-values.yaml -n monitoring
```
## Install Argo Workflow and Argo Events stacks
The following commands are also available on the [Official website](https://argoproj.github.io/argo-workflows/quick-start/)

Install Argo Events and Argo Workflow:
```bash
kubectl create ns argo

kubectl create ns argo-events

kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-events/stable/manifests/install.yaml

kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-events/stable/manifests/install-validating-webhook.yaml

# Install the eventbus
kubectl apply -n argo -f https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/eventbus/native.yaml

# Install Workflow 
kubectl apply -n argo -f https://raw.githubusercontent.com/argoproj/argo-workflows/master/manifests/install.yaml

# Install the Workflow with dependencies
kubectl apply -n argo -f https://raw.githubusercontent.com/argoproj/argo-workflows/master/manifests/quick-start-postgres.yaml
```

Forward the port:
```bash
kubectl -n argo port-forward deployment/argo-server 2746:2746
```

Apply the workflows:
```bash
kubectl apply -f argo-workflow-opensea-price-checker.yaml
kubectl apply -f argo-workflow-cron-generator-price-checker.yaml
kubectl apply -f telegram-webhook-listener.yaml
```
The first manifest contains the workflow to run the curl to the stats endpoint and verify the price based on the input values.

The second manifest contains the workflow to create a cron workflow that, by default, runs every 5 minutes and run the first manifest.

The third one is just an argo EventSource webhook. When an http request is received the in is triggered if an argo Sensor is combined with it.

The Sensor workflow contains a couple of place holders related to the telegram chat id and bot token.


## TODO
- [ ]  Produce http post request with the main workflow
- [ ]  Manage dinamically the sensitive data in the Sensor
- [X]  Push the Grafana Dashboard
- [ ]  Add Grafana Alarms based on the min/max price 
- [X]  Add cert-manager and let's encrypt with nginx-ingress controller (https://www.digitalocean.com/community/tutorials/how-to-set-up-an-nginx-ingress-with-cert-manager-on-digitalocean-kubernetes)
- [X]  Add Grafana SSO
- [ ]  Add Argo SSO with Keyclock (https://stackoverflow.com/questions/65918090/want-to-integrate-argo-server-with-keycloak)
- [ ]  Deploy the whole things automagically

> Default permissions are not enough to create automatically pods on Kubernetes hence you have to modify the RBAC associated to Argo Workflow