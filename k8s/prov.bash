#!/bin/bash

APP_REPO=${APP_REPO:-null}
LB_ADRESSES=${LB_ADRESSES:-192.168.100.85-192.168.100.98}
PROFILE_NAME=${PROFILE_NAME:-dev}
INFRA_PATH=${INFRA_PATH:-apps}
APP_PATH=${APP_PATH:-apps}
NAMESPACE=${NAMESPACE:-default}
INFRA_REPO=${INFRA_REPO:-https:\/\/github.com\/mc-istio\/infra-apps}

errorExit () {
    echo -e "\nERROR: $1"; echo
    exit 1
}

usage () {
    cat << END_USAGE
 <options>
--repo              : [required] A git repo for application
--lb                : [optional] Adresses for load balancers
--profile pr        : [optional] A profile name. Default is dev. Could be sit, uat, prod
--infra-path ip     : [optional] A custom infra app of apps path. Default is infra
--app-path app      : [optional] A custom business app of apps path. Default is apps
--ns                : [optional] A namespace to install argo apps. Default is default
--infra-repo        : [optional] A repo for infra
END_USAGE

    exit 1
}

processOptions () {
    # if [ $# -eq 0 ]; then
    #     usage
    # fi

    while [[ $# > 0 ]]; do
        case "$1" in
            --repo)
                APP_REPO=${2}; shift 2
            ;;
            --lb)
                LB_ADRESSES=${2}; shift 2
            ;;
            --profile)
                PROFILE_NAME=${2}; shift 2
            ;;
            --infra-path)
                INFRA_PATH=${2}; shift 2
            ;;
            --app-path)
                APP_PATH=${2}; shift 2
            ;; 
            --ns)
                NAMESPACE=${2}; shift 2
            ;;   
            --infra-repo)
                INFRA_REPO=${2}; shift 2
            ;;                                                   
            -h | --help)
                usage
            ;;
            *)
                usage
            ;;
        esac
    done
}

startMinikube() {
  minikube start \
    --profile "${PROFILE_NAME}" \
    --addons registry \
    --addons ingress \
    --addons metallb \
    --disk-size 40G \
    --memory 6G \
    --driver virtualbox

  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses: ["${LB_ADRESSES}"]
EOF
}

# Install argocd
installArgo () {
  kubectl --context="${PROFILE_NAME}" create namespace argocd
  kubectl --context="${PROFILE_NAME}"  apply -n argocd -f argo-install.yaml
  # https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  kubectl --context="${PROFILE_NAME}" wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=24h
}

# Install argocd cli 
installArgoCli () {
  curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/v2.2.5/argocd-darwin-amd64
  chmod +x /usr/local/bin/argocd
}

# Create infra apps
argoLogin () {
  argocd login cd.argoproj.io --core
}
  
# Create infra apps
createInfraApps () {
  argocd app create infra \
  --repo ${INFRA_REPO} \
  --path ${INFRA_PATH} \
  --dest-server https://kubernetes.default.svc \
  --sync-policy automated \
  --values values.yaml
  # --helm-set replicaCount=2
}

# Create business apps
createApps () {
  argocd app create apps \
  --repo ${APP_REPO} \
  --path ${APP_PATH} \
  --dest-server https://kubernetes.default.svc \
  --sync-policy automated \
  --values values.yaml
}

# Change namespace to argo
changeContextToArgo () {
  kubectl config set-context --current --namespace=argocd
}

# Change namespace to default
changeContextToDefault () {
  kubectl config set-context --current --namespace=default
}

main () {
    echo -e "\nRunning"

    echo "PROFILE_NAME: ${PROFILE_NAME}"
    echo "LB_ADRESSES:  ${LB_ADRESSES}"
    echo "INFRA_PATH:   ${INFRA_PATH}"
    echo "APP_PATH:     ${APP_PATH}"
    echo "NAMESPACE:    ${NAMESPACE}"
    echo "APP_REPO:     ${APP_REPO}"   
    echo "INFRA_REPO:   ${INFRA_REPO}"        

    startMinikube    
    installArgo    
    installArgoCli
    changeContextToArgo
    argoLogin
    createApps
    createInfraApps
    changeContextToDefault
}


processOptions $*
main

