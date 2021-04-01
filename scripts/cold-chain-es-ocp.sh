#!/bin/bash

##################
### PARAMETERS ###
##################

# Username and Password for an OpenShift user with cluster-admin privileges.
# cluster-admin privileges are required as this script deploys operators to
# watch all namespaces.
OCP_ADMIN_USER=${OCP_ADMIN_USER:=admin}
OCP_ADMIN_PASSWORD=${OCP_ADMIN_PASSWORD:=admin}scripts
CLUSTER_NAME=eda-dev
EVENTSTREAMS_NS=eventstreams

###################################
### DO NOT EDIT BELOW THIS LINE ###
###################################
### EDIT AT YOUR OWN RISK      ####
###################################


function install_operator() {
### function will create an operator subscription to the openshift-operators
###          namespace for CR use in all namespaces
### parameters:
### $1 - operator name
### $2 - operator channel
### $3 - operator catalog source
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ${1}
  namespace: openshift-operators
spec:
  channel: ${2}
  name: ${1}
  source: $3
  sourceNamespace: openshift-marketplace
EOF
}


############
### MAIN ###
############

### Login
# Make sure we don't have more than 1 argument
if [[ $# -gt 1 ]];then
 echo "Usage: sh cold-chain-es-ocp.sh [--skip-login]"
 exit 1
fi

# Check the argument is what we expect
if [[ $# -eq 1 ]];then
  if [[ "$1" == "--skip-login" ]]; then
    echo "Checking if you are logged into OpenShift..."
    oc whoami
    if [[ $? -gt 0 ]]; then
      echo "[ERROR] - An error occurred while checking if you are logged into OpenShift"
      exit 1
    fi
    echo "OK"
    SKIP_LOGIN="true"
  else
    echo "Usage: sh cold-chain-es-ocp.sh [--skip-login]"
    exit 1
  fi
fi

# Log in if we need to
if [ -z $SKIP_LOGIN ]; then
  oc login -u ${OCP_ADMIN_USER} -p ${OCP_ADMIN_PASSWORD}
  if [[ $? -gt 0 ]]; then
    echo "[ERROR] - An error occurred while logging into OpenShift"
    exit 1
  fi
fi

git clone https://github.com/ibm-cloud-architecture/vaccine-gitops.git

cd vaccine-gitops/environments
ROOTPATH=event-streams
PROJECT_NAME=vaccine-solution

### CREATE PROJECT
oc apply -f ${ROOTPATH}/infrastructure/namespace.yaml
oc apply -f ${ROOTPATH}/infrastructure/service-account.yaml

oc project ${PROJECT_NAME}

oc adm policy add-scc-to-user anyuid -z vaccine-runtime -n ${PROJECT_NAME}

### DEPLOY APPLICATION MICROSERVICES
oc apply -k apps/cold-chain

### WAIT FOR MICROSERVICE DEPLOYMENTS TO BECOME AVAILABLE
echo Waiting for application microservices to be available...
sleep 10
oc wait --for=condition=available deploy -l app.kubernetes.io/part-of=refarch-kc --timeout "-1s" -n vaccine-solution

### GET ROUTE FOR USER INTERFACE MICROSERVICE
echo "User Interface Microservice is available via http://$(oc get route kc-ui -o jsonpath='{.status.ingress[0].host}')"

### MANUAL STEP ### Send order event via browser
echo Login to the browser UI with \"eddie@email.com\" / \"Eddie\" and submit an order via the \"Initiate Orders\" tab
read -rsp $'Press any key to continue once an order has been submitted...\n' -n1 key

### Track kafka record via kafka-console-consumer and `oc rsh`
echo "Checking ORDER-COMMANDS topic for Kafka records produced by the order-command microservice..."
oc rsh my-cluster-kafka-0 bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --from-beginning --timeout-ms 10000 --topic order-commands

echo "Checking ORDERS topic for Kafka records produced by the order-command microservice..."
oc rsh my-cluster-kafka-0 bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --from-beginning --timeout-ms 10000 --topic orders
