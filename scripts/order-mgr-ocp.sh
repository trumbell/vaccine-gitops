#!/bin/bash

##################
### PARAMETERS ###
##################

# Username and Password for an OpenShift user with cluster-admin privileges.
# cluster-admin privileges are required as this script deploys operators to
# watch all namespaces.
OCP_ADMIN_USER=${OCP_ADMIN_USER:=admin}
OCP_ADMIN_PASSWORD=${OCP_ADMIN_PASSWORD:=admin}

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

### INSTALL Strimzi OPERATOR
### More info available via `oc describe packagemanifests strimzi-kafka-operator -n openshift-marketplace`

### Strimzi operator version stability appears to be not so stable, so this will
### specify the latest manually verified operator version for a given OCP version
### instead of just the default "stable" stream.
STRIMZI_OPERATOR_VERSION="strimzi-0.20.x"
OCP_VERSION=$(oc version -o json | jq -r ".openshiftVersion")

case ${OCP_VERSION} in
  4.4.*)
    echo "OpenShift v4.4.X detected. Installing 'strimzi-0.19.x'..."
    STRIMZI_OPERATOR_VERSION="strimzi-0.19.x"
    ;;
  4.5.*)
    echo "OpenShift v4.5.X detected. Installing 'strimzi-0.20.x'..."
    STRIMZI_OPERATOR_VERSION="strimzi-0.20.x"
    ;;
  *)
    STRIMZI_OPERATOR_VERSION="stable"
    ;;
esac

install_operator "strimzi-kafka-operator" "${STRIMZI_OPERATOR_VERSION}" "community-operators"


###TODO### Alternate implementation for `oc wait --for=condition=AtLatestKnown subscription/__operator_subscription__ --timeout 300s`
for operator in strimzi-kafka-operator
do
  counter=0
  desired_state="AtLatestKnown"
  until [[ ("$(oc get -o json -n openshift-operators subscription ${operator} | jq -r .status.state)" == "${desired_state}") || ( ${counter} == 60 ) ]]
  do
    echo Waiting for ${operator} operator to be deployed...
    ((counter++))
    sleep 5
  done
done

### CREATE PROJECT & KAFKA INFRASTRUCTURE
oc apply -k dev/infrastructure/

oc project vaccine-solution

oc adm policy add-scc-to-user anyuid -z vaccine-runtime -n vaccine-solution

echo Waiting for Kafka cluster to be available...
oc wait --for=condition=ready kafka vaccine-kafka --timeout "-1s" -n vaccine-solution

### DEPLOY APPLICATION MICROSERVICES
oc apply -k dev/apps/order-mgt

### WAIT FOR MICROSERVICE DEPLOYMENTS TO BECOME AVAILABLE
echo Waiting for application microservices to be available...
sleep 10
oc wait --for=condition=available deploy -l app.kubernetes.io/part-of=refarch-kc --timeout "-1s" -n vaccine-solution
