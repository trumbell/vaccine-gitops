#!/bin/bash
scriptDir=$(dirname $0)

##################
### PARAMETERS ###
##################

source ${scriptDir}/env.sh

###################################
### DO NOT EDIT BELOW THIS LINE ###
###################################
### EDIT AT YOUR OWN RISK      ####
###################################
ENVPATH=environments/event-streams
SA_NAME=vaccine-runtime
SCRAM_USER=scram-user
TLS_USER=tls-user

############
### MAIN ###
############
source ${scriptDir}/login.sh
### Login
# Make sure we don't have more than 1 argument
if [[ $# -gt 1 ]];then
 echo "Usage: sh  `basename "$0"` [--skip-login]"
 exit 1
fi

validateLogin $1

source ${scriptDir}/defineProject.sh

createProjectAndServiceAccount $YOUR_PROJECT_NAME $SA_NAME

echo "#############"
echo "Define users" 
echo "#############"
source ${scriptDir}/defineUser.sh

if [[ -z $(oc get secret ${SCRAM_USER} -n ${KAFKA_NS} 2> /dev/null) ]]
then
    defineUser ${SCRAM_USER} ${KAFKA_CLUSTER_NAME} scram-user ${ENVPATH}
    # THERE IS A BUG in oc or kubectl kustomize that is not parsing the json
    # error: json: cannot unmarshal object into Go struct field Kustomization.patchesStrategicMerge of type patch.StrategicMerge
    oc apply -k  ${ENVPATH}/overlays -n ${KAFKA_NS}
    sleep 5
    
else
    echo "${SCRAM_USER} presents"
fi



if [[ -z $(oc get secret ${TLS_USER} -n ${KAFKA_NS} 2> /dev/null) ]]
then
    defineUser ${TLS_USER} ${KAFKA_CLUSTER_NAME} tls-user ${ENVPATH}
    oc apply -k  $ENVPATH/overlays -n ${KAFKA_NS}
    sleep 5
    
else
    echo "${TLS_USER} presents"
fi

echo "##########################"
echo "Copy user secrets to ${YOUR_PROJECT_NAME}" 
echo "##########################"
if [[ -z $(oc get secret ${TLS_USER} 2> /dev/null) ]]
then
   # As the project is personal to the user, we can keep a generic name for the secret
   oc get secret ${TLS_USER} -n ${KAFKA_NS} -o json | jq -r '.metadata.name="tls-user"' | jq -r '.metadata.namespace="'${YOUR_PROJECT_NAME}'"' | oc apply -f -
fi

if [[ -z $(oc get secret ${SCRAM_USER} 2> /dev/null) ]]
then
    # As the project is personal to the user, we can keep a generic name for the secret
    oc get secret ${SCRAM_USER} -n ${KAFKA_NS} -o json |  jq -r '.metadata.name="scram-user"' | jq -r '.metadata.namespace="'${YOUR_PROJECT_NAME}'"' | oc apply -f -
fi


if [[ -z $(oc get secret kafka-cluster-ca-cert 2> /dev/null) ]]
then
    oc get secret ${KAFKA_CLUSTER_NAME}-cluster-ca-cert -n ${KAFKA_NS} -o json | jq -r '.metadata.name="kafka-cluster-ca-cert"' |jq -r '.metadata.namespace="'${YOUR_PROJECT_NAME}'"' | oc apply -f -
fi


if [[ -z $(oc get secret postgresql-creds 2> /dev/null) ]]
then
  echo "#################"
  echo "Deploy postgresql"
  echo "#################"
  # secrets are defined in the kustomize file
  oc apply -k environments/postgres
fi 

echo "#####################################################"
echo "Create secrets for apps"
echo "#####################################################"
SCRAM_USER_PWD=$(oc get secret ${SCRAM_USER} -o jsonpath='{.data.password}' | base64 --decode)
KAFKA_BOOTSTRAP=$(oc get route -n ${KAFKA_NS} ${KAFKA_CLUSTER_NAME}-kafka-bootstrap -o jsonpath="{.status.ingress[0].host}:443")

if [[ -z $(oc get secret kafka-schema-registry 2> /dev/null) ]]
then
    oc create secret generic  kafka-schema-registry \
      --from-literal=SCHEMA_REGISTRY_URL=https://${SCRAM_USER}:${SCRAM_USER_PWD}@${SCHEMA_REGISTRY_URL} \
  
fi

if [[ -z $(oc get secret vaccine-order-secrets 2> /dev/null) ]]
then
    oc create secret generic vaccine-order-secrets \
    --from-literal=SHIPMENT_PLAN_TOPIC=$YOUR_SHIPMENT_PLAN_TOPIC \
    --from-literal=KAFKA_BOOTSTRAP_SERVERS=$INTERNAL_KAFKA_BOOTSTRAP_SERVERS \
    --from-literal=APP_TRANSPORTATIONURL=http://vaccine-transport-simulator.${YOUR_PROJECT_NAME}.svc/transportation

fi
if [[ -z $(oc get secret vaccine-transport-secrets 2> /dev/null) ]]
then
    oc create secret generic vaccine-transport-secrets \
    --from-literal=KAFKA_BOOTSTRAP_SERVERS=$EXTERNAL_KAFKA_BOOTSTRAP_SERVERS 
fi

if [[ -z $(oc get secret vaccine-oro-secrets 2> /dev/null) ]]
then
  
   oc create secret generic vaccine-oro-secrets \
    --from-literal=KAFKA_BROKERS=$EXTERNAL_KAFKA_BOOTSTRAP_SERVERS 
fi

echo "#####################################################"
echo "DEPLOY APPLICATION MICROSERVICES"
echo "#####################################################"

oc apply -k apps/order-optim-use-case
sleep 10
### GET ROUTE FOR USER INTERFACE MICROSERVICE
echo "User Interface Microservice is available via http://$(oc get route oc vaccine-order-mgt -o jsonpath='{.status.ingress[0].host}')"

echo "#############"
echo "# Done ! "
echo "#############"
oc get pods 
echo "#############"
echo "When you are done with the lab do: ... ./scripts/deleteOrderOptim.sh" 

