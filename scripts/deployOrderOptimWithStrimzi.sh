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

#################
### FUNCTIONS ###
#################

function register_avro_schemas(){
    ar_url=$1
    # Register Common Avro Schema
    topics="vaccine.reefer \
            vaccine.inventory \
            vaccine.transportation \
            vaccine.shipment.plan"
    echo "Register Avro schemas"
    for topic in ${topics}
    do
        # Register the schema
        echo -n "Register Avro schema for ${topic}'s value..."
        response=`curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-type: application/json; artifactType=AVRO" -H "X-Registry-ArtifactId: ${topic}-value" --data @../data/CloudEvent.avsc http://${ar_url}/api/artifacts`
        if [[ $response -ne 200 ]]; then echo "[ERROR] - An error occurred while registering the Avro Schema for ${topic}'s value" ; exit 1; fi
        echo "Done"
    done

    # Register Specific Avro Schema for Postgres CDC Order Events for topic vaccine.public.orderevents
    # Register the key
    echo -n "Register Avro schema for vaccine.public.orderevents' key..."
    response=`curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-type: application/json; artifactType=AVRO" -H "X-Registry-ArtifactId: vaccine.public.orderevents-key" --data @../data/OrderEventKey.avsc http://${ar_url}/api/artifacts`
    if [[ $response -ne 200 ]]; then echo "[ERROR] - An error occurred while registering the Avro Schema for vaccine.public.orderevents' key" ; exit 1; fi
    echo "Done"
    # Register the key
    echo -n "Register Avro schema for vaccine.public.orderevents' value..."
    response=`curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-type: application/json; artifactType=AVRO" -H "X-Registry-ArtifactId: vaccine.public.orderevents-value" --data @../data/OrderEventValue.avsc http://${ar_url}/api/artifacts`
    if [[ $response -ne 200 ]]; then echo "[ERROR] - An error occurred while registering the Avro Schema for vaccine.public.orderevents' value" ; exit 1; fi
    echo "Done"

    # List Avro Schemas
    echo "Avro Schemas registered in the Apicurio Registry: $(curl -s http://${ar_url}/api/artifacts)"
    echo "Done"
}

function delete_avro_schemas(){
    ar_url=$1
    echo "Delete existing schemas in your Apicruio Schema Registry"
    for artifact in `curl -s http://${ar_url}/api/artifacts | sed 's/\[//g' | sed 's/\]//g' | sed 's/"//g' | tr ',' '\n'` 
    do
        # Register the schema
        echo -n "Delete Avro schema with id ${artifact}..."
        response=`curl -s -o /dev/null -w "%{http_code}" -X DELETE http://${ar_url}/api/artifacts/${artifact}`
        if [[ ($response -ne 204) ]]; then echo "[ERROR] - An error occurred while deleting the Avro Schema with id ${artifact}" ; exit 1; fi
        echo "Done"
    done
    echo "Done"
}


############
### MAIN ###
############

# Make sure we don't have more than 1 argument
if [[ $# -gt 1 ]];then
 echo "Usage: sh  `basename "$0"` [--skip-login]"
 exit 1
fi

echo "##########################################################"
echo "## Vaccine Order Management and Optimization Deployment ##"
echo "##########################################################"

################
### 1. Login ###
################
echo
echo "1. Log into your OpenShift cluster"
echo "----------------------------------"

# Load login utilities
source ${scriptDir}/login.sh

# Log into your OCP cluster
validateLogin $1

if [[ $? -gt 0 ]]
then
    echo "[ERROR] - An error occurred while logging into your OpenShift cluster"
    exit 1
fi

################################################
### 2. OpenShift Project and Service Account ###
################################################
echo
echo "2. Create your OpenShift project and Service Account"
echo "----------------------------------------------------"

# Load project and SA utilities
source ${scriptDir}/defineProject.sh

# Create the Project, Service Account and appropriate admin policies
createProjectAndServiceAccount ${YOUR_PROJECT_NAME} ${SA_NAME}
if [[ $? -gt 0 ]]
then 
    echo "[ERROR] - An error occurred while creating your OpenShift project and Service Account"
    exit 1
fi

########################
### 3. Kafka Cluster ###
########################
echo
echo "3. Deploy the Kafka Cluser"
echo "--------------------------"

### Kafka Cluster 
echo "Check if the Kafka Cluster ${KAFKA_CLUSTER_NAME} already exists"
if [[ -z $(oc get kafkas.kafka.strimzi.io ${KAFKA_CLUSTER_NAME} -n ${YOUR_PROJECT_NAME} 2> /dev/null) ]]
then
    echo "Kafka Cluster does not exist yet"
    echo "Create Kafka Cluster with Strimzi"
    ${scriptDir}/deployStrimzi.sh --skip-login
    if [[ $? -gt 0 ]]; then echo "[ERROR] - An error occurred while deploying the Strimzi Kafka Cluster"; exit 1; fi
else
    echo "Kafka Cluster ${KAFKA_CLUSTER_NAME} already exists"
fi

### Kafka Cluster Certificate
echo
echo "Check if the Kafka Cluster CA certificate secret exists"
if [[ -z $(oc get secret kafka-cluster-ca-cert 2>/dev/null) ]]
then
    echo "Kafka Cluster CA certificate secret not found. Create it"
    oc get secret ${KAFKA_CLUSTER_NAME}-cluster-ca-cert -n ${YOUR_PROJECT_NAME} -o json | jq -r '.metadata.name="kafka-cluster-ca-cert"' | jq --arg project_name "${YOUR_PROJECT_NAME}" -r '.metadata.namespace=$project_name' | oc apply -f -
    if [[ $? -gt 0 ]]; then echo "[ERROR] - An error occurred while creating the Kafka Cluster CA certificate secret"; exit 1; else echo "Done"; fi
else
    echo "Kafka Cluster CA certificate secret already exists"
fi

### Kafka Topics Configmap
echo
echo "Create Kafka Topics configmap"
kafka_cluster_internal_listener=`oc get kafkas.kafka.strimzi.io ${KAFKA_CLUSTER_NAME} -o jsonpath="{.status.listeners[?(@.type=='tls')].bootstrapServers}"`
kafka_cluster_external_listener=`oc get kafkas.kafka.strimzi.io ${KAFKA_CLUSTER_NAME} -o jsonpath="{.status.listeners[?(@.type=='external')].bootstrapServers}"`
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: kafka-topics-cm
data:
  KAFKA_BOOTSTRAP_SERVERS: ${kafka_cluster_internal_listener}
  KAFKA_BOOTSTRAP_SERVERS_EXT: ${kafka_cluster_external_listener}
  ORDER_TOPIC: "vaccine.public.orderevents"
  REEFER_TELEMETRY_TOPIC: "vaccine.reefer.telemetry"
  SHIPMENT_PLAN_TOPIC: "vaccine.shipment.plan"
  INVENTORY_TOPIC:  "vaccine.inventory"
  TRANSPORTATION_TOPIC:  "vaccine.transportation"
  REEFER_TOPIC:  "vaccine.reefer"
  
EOF
if [[ $? -gt 0 ]]; then echo "[ERROR] - An error occurred while creating the Kafka Topics configmap"; exit 1; else echo "Done"; fi

############################
### 4. Apicurio Registry ###
############################
echo
echo "4. Deploy the Apicurio Registry"
echo "-------------------------------"
### Apicurio Registry
echo "Check if the Apicurio Registry ${APICURIO_REGISTRY_NAME} already exists"
if [[ -z $(oc get apicurioregistries.apicur.io ${APICURIO_REGISTRY_NAME} -n ${YOUR_PROJECT_NAME} 2> /dev/null) ]]
then
    echo "Apicurio Registry does not exist yet"
    echo "Create Apicurio Registry"
    ${scriptDir}/deployApicurio.sh --skip-login
    # Check the Apicurio Registry deployment went fine
    if [[ $? -gt 0 ]]; then echo "[ERROR] - An error occurred while deploying the Apicurio Registry" ; exit 1; fi
    ### Avro Schemas
    # Get Apricurio Registry url
    # The status.host parameter of the Apicurio Registry resource takes other values before taking the definite route.
    # ar_url=`oc get apicurioregistries.apicur.io ${APICURIO_REGISTRY_NAME} -n ${YOUR_PROJECT_NAME} -o jsonpath="{.status.host}"`
    echo -n "Waiting for the Apicurio Registry to be accessible..."
    ar_route=""
    counter=0
    until [[ ( ! -z "${ar_route}") || ( ${counter} == 20 ) ]]
    do
        ((counter++))
        echo -n "..."
        sleep 5
        ar_route=`oc get routes | grep ${APICURIO_REGISTRY_NAME} | awk '{print $1}'`
    done

    if [[ ${counter} == 20 ]]
    then
        echo
        echo "[ERROR] - Timeout occurred while waiting for the Apicurio Registry to be accessible"
        exit 1
    else
        ar_host_url=`oc get route ${ar_route} -o jsonpath="{.status.ingress[].host}"`
        ar_routerCanonicalHostname_url=`oc get route ${ar_route} -ojsonpath="{.status.ingress[].routerCanonicalHostname}"`
        ar_url="${ar_host_url}.${ar_routerCanonicalHostname_url}"
        counter=0
        until [[ ( "${ar_url}" == "${ar_host_url}" ) || ( ${counter} == 20 ) ]]
        do
            ((counter++))
            echo -n "..."
            sleep 5
            ar_route=`oc get routes | grep ${APICURIO_REGISTRY_NAME} | awk '{print $1}'`
            ar_host_url=`oc get route ${ar_route} -o jsonpath="{.status.ingress[].host}" 2>/dev/null`
        done
        if [[ ${counter} == 20 ]]
        then
            echo
            echo "[ERROR] - Timeout occurred while waiting for the Apicurio Registry to be accessible"
            exit 1
        else
            echo "Done"
        fi
        echo "Your Apicurio Registry is accessible at http://${ar_url}"
        register_avro_schemas "${ar_url}"
    fi

else
    echo "Apicruio Registry ${APICURIO_REGISTRY_NAME} already exists"
    ar_url=`oc get apicurioregistries.apicur.io ${APICURIO_REGISTRY_NAME} -o jsonpath="{.status.host}"`
    delete_avro_schemas "${ar_url}"
    register_avro_schemas "${ar_url}"
fi

### Create Schema Registry secret
echo
echo "Create the Schema Registry secret..."
ar_service=`oc get apicurioregistry ${APICURIO_REGISTRY_NAME} -o jsonpath="{.status.serviceName}"`
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: kafka-schema-registry
stringData:
  SCHEMA_REGISTRY_URL: http://${ar_service}:8080/api
EOF
if [[ $? -gt 0 ]]; then echo "[ERROR] - An error occurred while creating the Schema Registry secret"; exit 1; else echo "Done"; fi

### Create Schema Registry for Confluent compatibility secret
echo
echo "Create the Schema Registry for Confluent compatibility secret..."
ar_service=`oc get apicurioregistry ${APICURIO_REGISTRY_NAME} -o jsonpath="{.status.serviceName}"`
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: kafka-schema-registry-ccompat
stringData:
  SCHEMA_REGISTRY_URL: http://${ar_service}:8080/api/ccompat
EOF
if [[ $? -gt 0 ]]; then echo "[ERROR] - An error occurred while creating the Schema Registry for Confluent compatibility secret"; exit 1; else echo "Done"; fi

#####################
### 5. Postgresql ###
#####################
echo
echo "5. Deploy Postgresql"
echo "--------------------"
### Deploy Postgres
echo "Deploy Postgresql"
oc apply -k ../environments/postgres -n ${YOUR_PROJECT_NAME}
echo "Wait for Postgres to be deployed..."
oc wait pod --for=condition=Ready -l app=postgresql -n ${YOUR_PROJECT_NAME} --timeout=300s
if [[ $? -gt 0 ]]; then echo "[ERROR] - An error occurred while deploying Postgresql"; exit 1; else echo "Done"; fi

### Create Postgres connector secret
echo
echo "Check if the Postgres connector secret exists"
if [[ -z $(oc get secret postgres-connector 2>/dev/null) ]]
then
    echo "Postgres connector secret not found. Create it"
    cat <<EOF >> connector.properties
database-dbname=orderdb
database-hostname=postgres-db-postgresql
database-port=5432
database-server-name=vaccine
table-whitelist=public.orderevents
database-password=supersecret
database-user=postgres
schema-registry-url=http://${ar_service}:8080/api
EOF
    oc create secret generic postgres-connector --from-file=./connector.properties && rm -rf connector.properties
    if [[ $? -gt 0 ]]; then echo "[ERROR] - An error occurred while creating the Postgres connector secret"; exit 1; else echo "Done"; fi
else
    echo "Postgres connector secret already exists"
fi


#####################################################
### 6. Order Management for Postgres microservice ###
#####################################################
echo
echo "6. Deploy the Order Management for Postgresql microservice"
echo "----------------------------------------------------------"
### Deploy Order Management for Postgres microservice
echo "Deploy the Order Management for Postgres microservice"
oc apply -k ../apps/order-mgt -n $YOUR_PROJECT_NAME
echo "Wait for the Order Management for Postgres microservice to be deployed..."
oc wait pod --for=condition=Ready -l app=vaccineorderms -n ${YOUR_PROJECT_NAME} --timeout=300s
if [[ $? -gt 0 ]]; then echo "[ERROR] - An error occurred while deploying the Order Management for Postgres microservice"; exit 1; else echo "Done"; fi

#########################################
### 7. Kafka Connect and Postgres CDC ###
#########################################
echo
echo "7. Deploy Kafka Connect Cluster and Postgres CDC connector"
echo "----------------------------------------------------------"
### Deploy Kafka Connect
echo "Deploy Kakfa Connect Cluster and create Postgres CDC connector instance"
oc apply -k ../environments/kafkaconnect-strimzi
echo "Wait for the Kafka Connect Cluster to be deployed"
oc wait kafkaconnects.kafka.strimzi.io/${KAFKA_CONNECT_CLUSER_NAME}  --for=condition=Ready -n ${YOUR_PROJECT_NAME} --timeout=300s
if [[ $? -gt 0 ]]; then echo "[ERROR] - An error occurred while deploying the Kakfa Connect Cluster"; exit 1; else echo "Done"; fi
echo "Wait for the Postgres connector instance to be created"
oc wait kafkaconnectors.kafka.strimzi.io/${POSTGRES_CONNECTOR_NAME}  --for=condition=Ready -n ${YOUR_PROJECT_NAME} --timeout=300s
if [[ $? -gt 0 ]]; then echo "[ERROR] - An error occurred while creating the Postgres CDC connector instance"; exit 1; else echo "Done"; fi


##################################################
### 8. Vaccine Order Optimization microservice ###
##################################################
echo
echo "8. Deploy the Vaccine Order Optimization microservice"
echo "-----------------------------------------------------"
### Deploy Vaccine Order Optimization microservice
echo "Deploy the Vaccine Order Optimization microservice"
oc apply -k ../apps/voro -n $YOUR_PROJECT_NAME
echo "Wait for the Vaccine Order Optimization microservice to be deployed..."
oc wait pod --for=condition=Ready -l app=vaccine-order-optimizer -n ${YOUR_PROJECT_NAME} --timeout=300s
if [[ $? -gt 0 ]]; then echo "[ERROR] - An error occurred while deploying the Vaccine Order Optimization microservice"; exit 1; else echo "Done"; fi

echo
echo "********************"
echo "** CONGRATULATIONS!! You have successfully deployed the Vaccine Order Managemente and Optimization use case."
echo "********************"
echo
echo "You can now jump to the demo section for this use case at https://ibm-cloud-architecture.github.io/vaccine-solution-main/use-cases/order/#demo"