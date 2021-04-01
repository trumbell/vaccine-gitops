KAFKA_NS=eventstreams

echo "Define image registry "


echo "Install Event Streams Operator"


Echo "Create Eventstreams namespace"
oc create ns $KAFKA_NS
oc project $KAFKA_NS
Echo "Create an Event Streams instance"