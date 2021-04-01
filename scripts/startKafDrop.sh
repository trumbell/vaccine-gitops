cd $(dirname $0)
KAFKA_BROKERS=vaccine-kafka-kafka-bootstrap-jbsandbox.assets-arch-eda-6ccd7f378ae819553d37d5f2ee142bd6-0000.us-east.containers.appdomain.cloud:443
docker run -ti --rm -p 9000:9000 \
     -v $(pwd):/home \
    -e KAFKA_BROKERCONNECT=$KAFKA_BROKERS \
    -e KAFKA_PROPERTIES=$(cat kafka.properties | base64) \
    -e JVM_OPTS="-Xms32M -Xmx64M" \
    -e SERVER_SERVLET_CONTEXTPATH="/" \
    obsidiandynamics/kafdrop
