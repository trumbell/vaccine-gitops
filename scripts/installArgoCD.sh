#!/bin/bash
scriptDir=$(dirname $0)
ARGOCD_NS=argocd
source ${scriptDir}/login.sh

nspresent=$(oc get ns $ARGOCD_NS 2>/dev/null)

if [[ -z $nspresent ]]
then 
  oc new-project $ARGOCD_NS
  oc apply -k ./environments/argocd
  oc adm policy add-cluster-role-to-user cluster-admin -z argocd-application-controller -n $ARGDOC_NS
fi

for operator in argocd-operator
do
  counter=0
  desired_state="AtLatestKnown"
  until [[ ("$(oc get -o json -n $ARGDOC_NS subscription ${operator} | jq -r .status.state)" == "${desired_state}") || ( ${counter} == 60 ) ]]
  do
    echo Waiting for ${operator} operator to be deployed...
    ((counter++))
    sleep 5
  done
done