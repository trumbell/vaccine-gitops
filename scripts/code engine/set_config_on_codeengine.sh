#!/bin/bash

# Switch to openshift context and get secrets into yaml form
oc config use-context trumbell/c114-e-us-south-containers-cloud-ibm-com:30501/IAM#thrumbel@us.ibm.com
oc get secret kafka-cluster-ca-cert -o yaml > kafka-cluster-ca-cert.yaml
oc get secret tls-user -o yaml > tls-user.yaml
oc get secret scram-user -o yaml > scram-user.yaml

# EDIT ALL SECRETS TO REMOVE ALL UNNEEDED METADATA, LEAVING ONLY NAME IN METADATA

# Apply secrets to code engine kubernetes context

kubectl config set-context gevokcvgseu
oc apply -f kafka-cluster-ca-cert.yaml
oc apply -f tls-user.yaml
oc apply -f scram-user.yaml
