# Define user with kustomize and json patch

function defineUser {
    USER_NAME=$1
    CLUSTER_NAME=$2
    ENVPATH=$4
    BASENAME=$3
    echo ###########
    echo "Define user $USER_NAME in cluster $CLUSTER_NAME" 
    echo ###########

    cat <<EOF > $ENVPATH/overlays/user-patch.json
[
    {"op" : "replace",
    "path": "/metadata/name",
    "value": "$USER_NAME"},
    {"op" : "replace",
     "path": "/metadata/labels",
     "value": {"eventstreams.ibm.com/cluster": "$CLUSTER_NAME"}
    }
]
EOF
    
    cat <<EOF > $ENVPATH/overlays/kustomization.yaml
bases:
  - ../base
patches:
- path: user-patch.json
  target:
    kind: KafkaUser
    name: $BASENAME
EOF
kustomize build $ENVPATH/overlays/ > $ENVPATH/overlays/$USER_NAME.yaml
}
