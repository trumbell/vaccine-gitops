#!/bin/bash
scriptDir=$(dirname $0)

##################
### PARAMETERS ###
##################

### Make sure you have the appropriate values for the following variables in the env-strimzi.sh file
# YOUR_PROJECT_NAME="vaccine-solution"              # Default OpenShift project where this vaccine use case will be deployed into.
# KAFKA_CLUSTER_NAME="vaccine-kafka"                # Default name for the Kafka Cluster this use case deploys. 
# APICURIO_REGISTRY_NAME="vaccine-apicurioregistry" # Default name for the Apicurio Registry this use case deploys.

# Load environment variables
source ${scriptDir}/env-strimzi.sh

###################################
### DO NOT EDIT BELOW THIS LINE ###
###################################
### EDIT AT YOUR OWN RISK !!!  ####
###################################
### If values below are changed, review not only this script but also
### the yaml files under /apps and /environmnets
SA_NAME="vaccine-runtime"
SCRAM_USER="scram-user"
TLS_USER="tls-user"
KAFKA_CONNECT_CLUSER_NAME="vaccine-connect-cluster"
POSTGRES_CONNECTOR_NAME="vaccine-pg-connector"

echo
# Delete the Vaccine Order and Optimization component
echo "# Delete the Vaccine Order and Optimization component"
oc delete -k ../apps/voro 2> /dev/null

echo
# Delete the Kafka Connect cluster
echo "# Delete the Kafka Connect cluster"
oc delete -k ../environments/kafkaconnect-strimzi 2> /dev/null

echo
# Delete the Order Management for Postgres component
echo "# Delete the Order Management for Postgres component"
oc delete -k ../apps/order-mgt 2> /dev/null

echo
# Delete Postgres components
echo "# Delete Postgres components"
oc delete secret postgres-connector 2> /dev/null
oc delete -k ../environments/postgres 2> /dev/null

echo
# Delete Schema Registry secrets
echo "# Delete Schema Registry secrets"
oc delete secret kafka-schema-registry 2> /dev/null
oc delete secret kafka-schema-registry-ccompat 2> /dev/null

echo
# Delete the Apicurio Registry
echo "# Delete the Apicurio Registry"
oc delete -k ../environments/apicurio 2> /dev/null
# Wait for the Apicurio Registry to be deleted before uninstalling the operator
echo "# Wait for the Apicurio Registry to be deleted before uninstalling the operator"
apicurio_pods=`oc get pods | grep ${APICURIO_REGISTRY_NAME}-deployment 2>/dev/null`
until [[ ( -z "${apicurio_pods}") || ( ${counter} == 20 ) ]]
do
    ((counter++))
    sleep 5
    apicurio_pods=`oc get pods | grep ${APICURIO_REGISTRY_NAME}-deployment 2>/dev/null`
done
if [[ ${counter} == 20 ]]
then
    echo
    echo "[ERROR] - Timeout occurred while waiting for the Apicurio Registry to be deleted"
    exit 1
fi

echo
# Delete the Apicurio Registry Operator and other resources around
echo "# Delete the Apicurio Registry Operator and other resources around"
oc delete subscription apicurio-registry 2> /dev/null
oc delete csv apicurio-registry.v0.0.4-v1.3.2.final 2> /dev/null
oc delete operatorgroup jesus-auto 2> /dev/null
oc delete crd apicurioregistries.apicur.io 2> /dev/null

echo
# Delete Kafka Cluster configmap and secret
echo "# Delete Kafka Cluster configmap and secret"
oc delete configmap kafka-topics-cm 2> /dev/null
oc delete secret kafka-cluster-ca-cert 2> /dev/null

echo
# Delete the Kafka Cluster
echo "# Delete the Kafka Cluster"
oc delete -k ../environments/strimzi 2> /dev/null
# Wait for the Kafka Cluster to be deleted befored deleting the OpenShift project
echo "# Wait for the Kafka Cluster to be deleted befored deleting the OpenShift project"
kafka_pods=`oc get pods | grep ${KAFKA_CLUSTER_NAME} 2>/dev/null`
until [[ ( -z "${kafka_pods}") || ( ${counter} == 20 ) ]]
do
    ((counter++))
    sleep 5
    kafka_pods=`oc get pods | grep ${KAFKA_CLUSTER_NAME} 2>/dev/null`
done
if [[ ${counter} == 20 ]]
then
    echo
    echo "[ERROR] - Timeout occurred while waiting for the Kafka Cluster to be deleted"
    exit 1
fi

echo
# Delete any other Kafka Topic created as a result of the deployment of the above components
echo "# Delete any other Kafka Topic created as a result of the deployment of the above components"
for topic in `oc get KafkaTopics.kafka.strimzi.io | grep vaccine | awk '{print $1}'`
do 
  oc delete KafkaTopics.kafka.strimzi.io $topic
done

echo
# Delete the OpenShift project
echo "# Delete the OpenShift project"
oc delete project ${YOUR_PROJECT_NAME}