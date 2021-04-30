#!/bin/bash
scriptDir=$(dirname $0)
echo "Get jars for Postgres and Debezium"
DEBEZIUM_VERSION=1.5.0.Final
APICURIO_VERSION=2.0.0.Final
ENV_KCONNECT=${scriptDir}/../environments/kafkaconnect/base/connectors
echo "Get Debezium postgres jars jars"
cd ${ENV_KCONNECT}

if [[ ! -f debezium-connector-postgres-${DEBEZIUM_VERSION}-plugin.tar.gz ]]
then
 curl -O https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/${DEBEZIUM_VERSION}/debezium-connector-postgres-${DEBEZIUM_VERSION}-plugin.tar.gz  
 tar -xvf debezium-connector-postgres-${DEBEZIUM_VERSION}-plugin.tar.gz 
fi 

if [[ ! -f apicurio-registry-distro-connect-converter-${APICURIO_VERSION}.tar.gz ]]
then
 curl -O https://repo1.maven.org/maven2/io/apicurio/apicurio-registry-distro-connect-converter/${APICURIO_VERSION}/apicurio-registry-distro-connect-converter-${APICURIO_VERSION}.tar.gz
 tar -xvf apicurio-registry-distro-connect-converter-${APICURIO_VERSION}.tar.gz -C debezium-connector-postgres/
fi

oc apply -k ${ROOTPATH}/infrastructure/kafkaconnect -n ${EVENTSTREAMS_NS}
oc start-build my-connect-cluster-connect --from-dir ${ROOTPATH}/infrastructure/kafkaconnect/base/my-plugins/ --follow -n ${EVENTSTREAMS_NS}

oc apply -f ${ROOTPATH}/infrastructure/kafkaconnect/base/pg-connector.yaml -n ${EVENTSTREAMS_NS}


oc describe kafkaconnector pg-connector -n ${EVENTSTREAMS_NS}