
#!/bin/bash
scriptDir=$(dirname $0)
oc delete -k ${scriptDir}/../apps/cold-chain-use-case
