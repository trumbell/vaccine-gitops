#!/bin/bash

##################
### PARAMETERS ###
##################



###################################
### DO NOT EDIT BELOW THIS LINE ###
###################################
### EDIT AT YOUR OWN RISK      ####
###################################

### Define the Kafka connector source to image
oc apply -k ${ROOTPATH}/infrastructure/kafkaconnect -n ${EVENTSTREAMS_NS}
oc start-build my-connect-cluster-connect --from-dir ${ROOTPATH}/infrastructure/kafkaconnect/base/my-plugins/ --follow -n ${EVENTSTREAMS_NS}

oc apply -f ${ROOTPATH}/infrastructure/kafkaconnect/base/pg-connector.yaml -n ${EVENTSTREAMS_NS}


oc describe kafkaconnector pg-connector -n ${EVENTSTREAMS_NS}

