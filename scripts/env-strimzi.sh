##################
### PARAMETERS ###
##################

# Username and Password for an OpenShift user with cluster-admin privileges.
# cluster-admin privileges are required as this script deploys operators to
# watch all namespaces.
OCP_ADMIN_USER=${OCP_ADMIN_USER:=admin}
OCP_ADMIN_PASSWORD=${OCP_ADMIN_PASSWORD:=admin}
# if you change cluster name then you need to change the strimzi yaml files.
KAFKA_CLUSTER_NAME="vaccine-kafka"
# Default name for the Apicurio Registry this use case deploys.
APICURIO_REGISTRY_NAME="vaccine-apicurioregistry"
# project name / namespace where event streams or kafka is defined
YOUR_PROJECT_NAME="vaccine-solution"
KAFKA_NS=vaccine-solution
YOUR_SUFFIX=jb
YOUR_TELEMETRIES_TOPIC=reefer.telemetries
YOUR_REEFER_TOPIC=vaccine.reefers
YOUR_ALERT_TOPIC=vaccine.reeferalerts
YOUR_SHIPMENT_PLAN_TOPIC=vaccine.shipment.plans
EXTERNAL_KAFKA_BOOTSTRAP_SERVERS=${KAFKA_CLUSTER_NAME}-kafka-bootstrap-${KAFKA_NS}.assets-arch-eda-6ccd7f378ae819553d37d5f2ee142bd6-0000.us-east.containers.appdomain.cloud:443
INTERNAL_KAFKA_BOOTSTRAP_SERVERS=${KAFKA_CLUSTER_NAME}-kafka-bootstrap.${KAFKA_NS}.svc:9093
FREEZER_MGR_URL=http://freezer-mgr-${YOUR_PROJECT_NAME}.assets-arch-eda-6ccd7f378ae819553d37d5f2ee142bd6-0000.us-east.containers.appdomain.cloud
SCHEMA_REGISTRY_URL=localhost:9094
# Cloud pak for data user - keep it empty so the code will not use anomaly detection WML
PREDICTION_ENABLED=false
YOUR_CP4D_USER=auserforcp4d
YOUR_CP4D_API_KEY=notearealkey
# URL to authenticate a user to get a JWT token
YOUR_CP4D_AUTH_URL=https://notarealdomain.com
ANOMALY_DETECTION_URL=https://notarealdomain.com