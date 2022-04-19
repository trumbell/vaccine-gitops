#!/bin/bash
scriptDir=$(dirname $0)

# First command line arg sets certs dir
if [[ $# -gt 1 ]];then
 certDir=$1
else
 certDir=certs
fi

# Seccond command line arg sets namespace
if [[ $# -gt 2 ]];then
 namespace=$2
else
 namespace=trumbell
fi

oc get secret kafka-cluster-ca-cert -n ${namespace} -o jsonpath='{.data.ca\.crt}' | base64 -d > ${scriptDir}/${certDir}/ca.crt

oc get secret scram-user -n ${namespace} -o jsonpath='{.data.password}' | base64 -d > ${scriptDir}/${certDir}/scram-user.password

oc get secret scram-user -n ${namespace} -o jsonpath='{.data.sasl\.jaas\.config}' | base64 -d > ${scriptDir}/${certDir}/scram-user.sasl.jaas.config

oc get secret tls-user -n ${namespace} -o jsonpath='{.data.user\.p12}' | base64 -d > ${scriptDir}/${certDir}/user.p12

oc get secret tls-user -n ${namespace} -n trumbell -o jsonpath='{.data.user\.password}' | base64 -d > ${scriptDir}/${certDir}/user.password

# Make the truststore - this won't work if user-truststore.jks already has the CARoot alias in it
# Requires new password - enter any password twice
keytool -keystore ${scriptDir}/${certDir}/user-truststore.jks -alias CARoot -import -file ${scriptDir}/${certDir}/ca.crt

# Make the keystore - this won't work if user-keystore.jks already exists
# Requires new password - enter any password twice - then update this password in client-ssl-auth.properties
# then requires user.password - copy contents of user.password and paste at prompt
keytool -importkeystore -srckeystore ${scriptDir}/${certDir}/user.p12 -srcstoretype pkcs12 -destkeystore ${scriptDir}/${certDir}/user-keystore.jks -deststoretype jks
