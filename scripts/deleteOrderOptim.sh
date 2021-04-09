#!/bin/bash
scriptDir=$(dirname $0)
oc delete -k ${scriptDir}/../apps/order-optim-use-case
oc delete secret vaccine-order-secrets
oc delete secret vaccine-transport-secrets
oc delete secret vaccine-oro-secrets
