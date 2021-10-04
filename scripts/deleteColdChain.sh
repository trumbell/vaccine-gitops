
#!/bin/bash
scriptDir=$(dirname $0)
oc delete -k ${scriptDir}/../apps/cold-chain-use-case
oc delete -k ${scriptDir}/../apps/freezer-mgr
oc delete -k ${scriptDir}/../environments/strimzi
oc delete kafkauser scram-user
oc delete secret freezer-mgr-secret
oc delete secret reefer-monitoring-agent-secret
oc delete secret reefer-simul-secret
oc delete serviceaccount vaccine-runtime
