#!/bin/bash

##################
### PARAMETERS ###
##################

# Username and Password for an OpenShift user with cluster-admin privileges.
# cluster-admin privileges are required as this script deploys operators to
# watch all namespaces.
OCP_ADMIN_USER=${OCP_ADMIN_USER:=admin}
OCP_ADMIN_PASSWORD=${OCP_ADMIN_PASSWORD:=admin}
CLUSTER_NAME=eda-dev
EVENTSTREAMS_NS=eventstreams


###################################
### DO NOT EDIT BELOW THIS LINE ###
###################################
### EDIT AT YOUR OWN RISK      ####
###################################
PROJECT_NAME=vaccine-solution

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
 echo "Usage: sh order-mgr-ocp.sh [--skip-login]"
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
    echo "Usage: sh order-mgr-ocp.sh [--skip-login]"
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

### CREATE PROJECT
oc apply -f ${ROOTPATH}/infrastructure/namespace.yaml
oc apply -f ${ROOTPATH}/infrastructure/service-account.yaml

oc project ${PROJECT_NAME}

oc adm policy add-scc-to-user anyuid -z vaccine-runtime -n ${PROJECT_NAME}

### Deploy postgres
echo "------------------ Deploy Postgresql-------------------"
oc apply -k ${ROOTPATH}/infrastructure/postgres

### Define kafka users
present=$(oc get kafkausers.eventstreams.ibm.com -n eventstreams | grep tls-user)
if [[ -z $present ]]
then
  oc apply -f ${ROOTPATH}/infrastructure/eventstreams/es-user.yaml
fi

### Define kafka config
oc apply -f ${ROOTPATH}/infrastructure/eventstreams/kafka-configmap.yaml -n ${PROJECT_NAME}


SCRAM_USER=scram-user
### Work on the different SCRAM authentication
oc get secret ${SCRAM_USER} -n ${EVENTSTREAMS_NS} -o json | jq -r '.metadata.namespace="'${PROJECT_NAME}'"' | oc apply -f -

### Work on the different TSL authentication
TLS_USER=tls-user
oc get secret ${TLS_USER} -n ${EVENTSTREAMS_NS} -o json | jq -r '.metadata.namespace="'${PROJECT_NAME}'"' | oc apply -f -

oc get secret ${CLUSTER_NAME}-cluster-ca-cert -n ${EVENTSTREAMS_NS} -o json | jq -r '.metadata.name="kafka-cluster-ca-cert"' |jq -r '.metadata.namespace="'${PROJECT_NAME}'"' | oc apply -f -

### Define the Kafka connector source to image
oc apply -k ${ROOTPATH}/infrastructure/kafkaconnect -n ${EVENTSTREAMS_NS}
oc start-build my-connect-cluster-connect --from-dir ${ROOTPATH}/infrastructure/kafkaconnect/base/my-plugins/ --follow -n ${EVENTSTREAMS_NS}

oc apply -f ${ROOTPATH}/infrastructure/kafkaconnect/base/pg-connector.yaml -n ${EVENTSTREAMS_NS}


oc describe kafkaconnector pg-connector -n ${EVENTSTREAMS_NS}

cd ..
### DEPLOY APPLICATION MICROSERVICES
# oc apply -f ./apps/order-mgt/base/order-mgt-configmap.yaml
# oc apply -f ./apps/order-mgt/base/order-mgt-deployconfig.yaml
oc apply -k ./apps/order-mgt/

### WAIT FOR MICROSERVICE DEPLOYMENTS TO BECOME AVAILABLE
echo Waiting for application microservices to be available...
sleep 10out "-1s" 
oc wait --for=condition=available deploymentconfig -l app=vaccineorderms --timeout "-1s" -n ${PROJECT_NAME}

vaccineorderaddress=$(oc get route  vaccineorderms -o jsonpath='{.status.ingress[0].host}')
echo "###################################"
echo "User Interface Microservice is available via http://${vaccineorderaddress}"
echo "Existing orders"
curl http://${vaccineorderaddress}/api/v1/orders
echo "Add one order"
curl -X POST "http://${vaccineorderaddress}/api/v1/orders" -H  "accept: application/json" -H  "Content-Type: application/json" -d "{\"askingOrganization\":\"UK\",\"deliveryDate\":\"02-27-2021\",\"deliveryLocation\":\"London\",\"priority\":2,\"quantity\":100,\"vaccineType\":\"covid-19\"}"

