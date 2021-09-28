#!/bin/bash
scriptDir=$(dirname $0)

##################
### PARAMETERS ###
##################

source ${scriptDir}/env-strimzi.sh

###################################
### DO NOT EDIT BELOW THIS LINE ###
###################################
### EDIT AT YOUR OWN RISK      ####
###################################
ENVPATH=environments/strimzi
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

# Add a check for Strimzi operator installed and available
# strimziInstalled=$(oc get pods | grep kafka 2> /dev/null)
# if [[ -z $stimziInstalled ]]
# then
#   echo "Install Strimzi"
#   ${scriptDir}/deployStrimzi.sh --skip-login
# fi

# Then check for kafka cluster
kafkaRunning=$(oc get pods | grep kafka 2> /dev/null)
if [[ -z $kafkaRunning ]]
then
  echo "Create Kafka Cluster with Strimzi"
  ${scriptDir}/deployKafka.sh --skip-login
fi

echo "#####################################################"
echo "Create secrets for topic name and bootstrap server URL"
echo "#####################################################"

if [[ -z $(oc get secret kafka-cluster-ca-cert 2> /dev/null) ]]
then
    echo "kafka-cluster-ca-cert not found copy from ${KAFKA_CLUSTER_NAME}-cluster-ca-cert"
    oc get secret ${KAFKA_CLUSTER_NAME}-cluster-ca-cert -n ${KAFKA_NS} -o json | jq -r '.metadata.name="kafka-cluster-ca-cert"' |jq -r '.metadata.namespace="'${PROJECT_NAME}'"' | oc apply -f -
fi

KAFKA_BOOTSTRAP=$(oc get route -n ${KAFKA_NS} ${KAFKA_CLUSTER_NAME}-kafka-bootstrap -o jsonpath="{.status.ingress[0].host}:443")
EXTERNAL_KAFKA_BOOTSTRAP_SERVERS=`oc get kafka -n ${KAFKA_NS} ${KAFKA_CLUSTER_NAME} -o jsonpath='{.status.listeners[?(@.type=="external")].bootstrapServers}{"\n"}'`

if [[ -z $(oc get secret freezer-mgr-secret 2> /dev/null) ]]
then
    echo "freezer-mgr-secret not found -> create it"
    
    oc create secret generic freezer-mgr-secret \
    --from-literal=KAFKA_BOOTSTRAP_SERVERS=$INTERNAL_KAFKA_BOOTSTRAP_SERVERS \
    --from-literal=REEFER_TOPIC=$YOUR_REEFER_TOPIC \
    --from-literal=ALERTS_TOPIC=$YOUR_ALERT_TOPIC \
    --from-literal=KAFKA_USER=$TLS_USER \
    --from-literal=KAFKA_CA_CERT_NAME=kafka-cluster-ca-cert 
fi

echo "#####################################################"
echo "FIRST DEPLOY FREEZER_MGR MICROSERVICE"
echo "#####################################################"
oc apply -k apps/freezer-mgr
echo "Waiting for freezer-mgr pod to start running"
counter=0
desired_state="Succeeded"
until [[ ("$(oc get pod -n ${YOUR_PROJECT_NAME} freezer-mgr-1-deploy -o jsonpath="{.status.phase}")" == "${desired_state}") || ( ${counter} == 20 ) ]]
do
  ((counter++))
  echo -n "..."
  sleep 5
done
if [[ ${counter} == 20 ]]
then
  echo
  echo "[ERROR] - Timeout occurred while starting freezer-mgr"
  exit 1
else
  echo "Done"
fi

# Then get freezer-mgr url
FREEZER_MGR_URL=$(oc get route freezer-mgr -o jsonpath="http://{.status.ingress[0].host}")

# Then set up more secrets
if [[ -z $(oc get secret reefer-simul-secret) ]]
then
    echo "reefer-simul-secret not found -> create it"
    oc create secret generic reefer-simul-secret \
    --from-literal=KAFKA_BOOTSTRAP_SERVERS=$EXTERNAL_KAFKA_BOOTSTRAP_SERVERS \
    --from-literal=KAFKA_MAIN_TOPIC=$YOUR_TELEMETRIES_TOPIC \
    --from-literal=FREEZER_MGR_URL=$FREEZER_MGR_URL
fi
if [[ -z $(oc get secret reefer-monitoring-agent-secret 2> /dev/null) ]]
then
    echo "reefer-monitoring-agent-secret  not found -> create it"
    oc create secret generic reefer-monitoring-agent-secret \
    --from-literal=KAFKA_BOOTSTRAP_SERVERS=$INTERNAL_KAFKA_BOOTSTRAP_SERVERS \
    --from-literal=CP4D_USER=$YOUR_CP4D_USER \
    --from-literal=CP4D_API_KEY=$YOUR_CP4D_API_KEY \
    --from-literal=CP4D_AUTH_URL=$YOUR_CP4D_AUTH_URL \
    --from-literal=ANOMALY_DETECTION_URL=$ANOMALY_DETECTION_URL
fi


echo "#####################################################"
echo "DEPLOY APPLICATION MICROSERVICES"
echo "#####################################################"
oc apply -k apps/cold-chain-use-case

echo "#############"
echo "# Done ! "
echo "#############"
oc get pods 
echo "#############"
echo "When you are done with the lab do: ... ./scripts/deleteColdChain.sh" 


sleep 5

$scriptDir/getTestColdChainServices.sh

