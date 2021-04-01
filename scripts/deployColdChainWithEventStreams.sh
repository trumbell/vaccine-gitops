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

echo "#####################################################"
echo "Create secret for topic name and bootstrap server URL"
echo "#####################################################"

if [[ -z $(oc get secret freezer-mgr-secret 2> /dev/null) ]]
then
    oc create secret generic freezer-mgr-secret \
    --from-literal=KAFKA_BOOTSTRAP_SERVERS=$INTERNAL_KAFKA_BOOTSTRAP_SERVERS \
    --from-literal=REEFER_TOPIC=$YOUR_REEFER_TOPIC \
    --from-literal=ALERTS_TOPIC=$YOUR_ALERT_TOPIC \
    --from-literal=KAFKA_USER=$TLS_USER \
    --from-literal=KAFKA_CA_CERT_NAME=kafka-cluster-ca-cert 
fi


if [[ -z $(oc get secret reefer-simul-secret 2> /dev/null) ]]
then
    oc create secret generic reefer-simul-secret \
    --from-literal=KAFKA_BOOTSTRAP_SERVERS=$EXTERNAL_KAFKA_BOOTSTRAP_SERVERS \
    --from-literal=KAFKA_MAIN_TOPIC=$YOUR_TELEMETRIES_TOPIC \
    --from-literal=FREEZER_MGR_URL=$FREEZER_MGR_URL

fi
if [[ -z $(oc get secret reefer-monitoring-agent-secret 2> /dev/null) ]]
then
    oc create secret generic reefer-monitoring-agent-secret \
    --from-literal=KAFKA_BOOTSTRAP_SERVERS=$INTERNAL_KAFKA_BOOTSTRAP_SERVERS \
    --from-literal=PREDICTION_ENABLED=$PREDICTION_ENABLED \
    --from-literal=CP4D_USER=$YOUR_CP4D_USER \
    --from-literal=CP4D_API_KEY=$YOUR_CP4D_API_KEY \
    --from-literal=CP4D_AUTH_URL=$YOUR_CP4D_AUTH_URL \
    --from-literal=ANOMALY_DETECTION_URL=$ANOMALY_DETECTION_URL
fi

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
# As the project is personal to the user, we can keep a generic name for the secret
oc get secret ${SCRAM_USER} -n ${KAFKA_NS} -o json |  jq -r '.metadata.name="scram-user"' | jq -r '.metadata.namespace="'${YOUR_PROJECT_NAME}'"' | oc apply -f -

if [[ -z $(oc get secret ${TLS_USER} -n ${KAFKA_NS} 2> /dev/null) ]]
then
    defineUser ${TLS_USER} ${KAFKA_CLUSTER_NAME} tls-user ${ENVPATH}
    oc apply -k  $ENVPATH/overlays -n ${KAFKA_NS}
    sleep 5
    
else
    echo "${TLS_USER} presents"
fi

# As the project is personal to the user, we can keep a generic name for the secret
oc get secret ${TLS_USER} -n ${KAFKA_NS} -o json | jq -r '.metadata.name="tls-user"' | jq -r '.metadata.namespace="'${PROJECT_NAME}'"' | oc apply -f -

if [[ -z $(oc get secret kafka-cluster-ca-cert 2> /dev/null) ]]
then
    oc get secret ${KAFKA_CLUSTER_NAME}-cluster-ca-cert -n ${KAFKA_NS} -o json | jq -r '.metadata.name="kafka-cluster-ca-cert"' |jq -r '.metadata.namespace="'${PROJECT_NAME}'"' | oc apply -f -
fi



echo "DEPLOY APPLICATION MICROSERVICES"
oc apply -k apps/cold-chain-use-case

### GET ROUTE FOR USER INTERFACE MICROSERVICE

echo "#############"
echo "# Done ! "
echo "#############"
oc get pods 
echo "#############"
echo "When you are done with the lab do: ... ./scripts/deleteColdChain.sh" 

sleep 5

$scriptDir/getTestColdChainServices.sh
