# Gitops for vaccine solution

This repository includes the set of configuration files for the vaccine solution deployment and uses [Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) to define the Kubernetes resources needed to run the different use cases and environments.

The tree has the following structure, with `environment` to define the different Kafka flavor, Postgresql, Apicurio, and the `apps` folder to define application components to use depending of the use cases (cold-chain, order-optimization, anomaly detection).

## apps structure

We can support three use cases in the current solution: cold chain monitoring, order management optimization  and anomaly detection. So the apps folder has those three use cases defined with Kustomize and leverage all the component declarations.

```
├── apps
│   ├── anomaly-detection-use-case
│   │   ├── base
│   │   │   └── kustomization.yaml
│   │   └── kustomization.yaml
│   ├── cold-chain-use-case
│   │   ├── base
│   │   │   └── kustomization.yaml
│   │   ├── kustomization.yaml
│   │   └── overlays
│   │       ├── kafka-topics.yaml
│   │       └── kustomization.yaml
│   ├── order-optim-use-case
│   │   ├── base
│   │   │   └── kustomization.yaml
│   │   ├── kustomization.yaml
│   │   └── overlays
│   │       ├── kafka-topics.yaml
│   │       └── kustomization.yaml
```

Then each component of the solution will have its own set of descriptors to deploy then independently. 

```
── apps
│   ├── freezer-mgr
│   │   ├── base
│   │   │   ├── deployment.yaml
│   │   │   ├── kustomization.yaml
│   │   │   └── openshift.yml
│   │   └── kustomization.yaml
│   ├── monitoring-agent
│   │   ├── base
│   │   │   ├── configmap.yaml
│   │   │   ├── deployment.yaml
│   │   │   ├── rolebinding.yaml
│   │   │   ├── route.yaml
│   │   │   ├── service-account.yaml
│   │   │   └── service.yaml
│   │   └── kustomization.yaml
│   ├── order-mgt
│   │   ├── base
│   │   │   ├── configmap.yaml
│   │   │   ├── deployconfig.yaml
│   │   │   ├── rolebinding.yaml
│   │   │   ├── route.yaml
│   │   │   ├── secret.yaml
│   │   │   └── service.yaml
│   │   └── kustomization.yaml
│   ├── reefer-simulator
│   │   ├── base
│   │   │   ├── configmap.yaml
│   │   │   ├── deployment.yaml
│   │   │   ├── route.yaml
│   │   │   └── service.yaml
│   │   └── kustomization.yaml
│   ├── transportation
│   │   ├── base
│   │   │   ├── configmap.yaml
│   │   │   ├── deployconfig.yaml
│   │   │   ├── rolebinding.yaml
│   │   │   ├── route.yaml
│   │   │   ├── secret.yaml
│   │   │   └── service.yaml
│   │   └── kustomization.yaml
│   └── voro
│       ├── base
│       │   ├── configmap.yaml
│       │   ├── deployment.yaml
│       │   ├── route.yaml
│       │   ├── secret.yaml
│       │   └── service.yaml
│       └── kustomization.yaml
```

In an attempt to create a CI process that minimizes the amount of infrastructure overhead, our CI process utilizes [GitHub Actions](https://github.com/features/actions) for automated docker image builds. So each of the component of the solution has a workflow to build the docker image: upon a code push to the `main` branch of a given repository, GitHub Actions will perform a docker build on the source code, create a new tag for the commit, tag the repository, tag the docker image, and push to the `ibmcase` Docker Hub organization.

## Environments

The `environment` is deployable to any Kubernetes or OpenShift cluster and provides its own dedicated backing services.

Prerequisites:

- Depending if you use Strimzi or EventStreams, or both those operators must be installed, and configured to watch all namespaces.
- You are logged into the OpenShift Cluster with `oc login...`

```
├── environments
│   ├── event-streams
│   │   ├── base
│   │   │   ├── IBMCatalogSource.yaml
│   │   │   ├── es-topics.yaml
│   │   │   ├── eventstreams-minimal-prod.yaml
│   │   │   ├── eventstreams-prod-3-brokers.yaml
│   │   │   ├── kafka-configmap.yaml
│   │   │   ├── kustomization\ copy.yaml
│   │   │   ├── kustomization.yaml
│   │   │   ├── namespace.yaml
│   │   │   ├── scram-user\ copy.yaml
│   │   │   ├── scram-user.yaml
│   │   │   ├── tls-user\ copy.yaml
│   │   │   └── tls-user.yaml
│   │   ├── infrastructure
│   │   │   ├── kustomization.yaml
│   │   │   └── service-account.yaml
│   │   └── overlays
│   │       ├── kustomization.yaml
│   │       └── user-patch.json
│   ├── postgres
│   │   ├── base
│   │   │   ├── kustomization.yaml
│   │   │   ├── statefulset.yaml
│   │   │   ├── svc-headless.yaml
│   │   │   └── svc.yaml
│   │   ├── kustomization.yaml
│   │   └── overlays
│   │       ├── kustomization.yaml
│   │       └── service-account-patch.yaml
│   └── strimzi
│       ├── base
│       │   ├── kafka-cluster.yaml
│       │   ├── kafka-topics.yaml
│       │   ├── kafka-users.yaml
│       │   └── kustomization.yaml
│       └── kustomization.yaml
```

### Defining Strimzi Kafka cluster, service account

* The following commands are a one-time setup to create namespace, Kafka cluster and other entities:

```shell
oc apply -k environments/strimzi/
# Verify the two pods are running
oc get pods
# NAME                          READY   STATUS    RESTARTS   AGE
# vaccine-kafka-entity-operator-6c48b45c4b-pt7lw   3/3     Running   0          4m39s
# vaccine-kafka-kafka-0                            1/1     Running   0          5m12s
# vaccine-kafka-kafka-1                            1/1     Running   0          5m12s
# vaccine-kafka-kafka-2                            1/1     Running   0          5m11s
# vaccine-kafka-kafka-exporter-6c7d77d698-28697    1/1     Running   0          4m6s
# vaccine-kafka-zookeeper-0                        1/1     Running   0          5m51s
# vaccine-kafka-zookeeper-1                        1/1     Running   0          5m51s
# vaccine-kafka-zookeeper-2                        1/1     Running   0          5m51s

# The following command is required only if targeting an OpenShift cluster

oc adm policy add-scc-to-user anyuid -z vaccine-runtime -n vaccine-solution
```

* Verify the user created

```shell
oc get kafkausers
```

* Verify the topics created

```shell
oc get kafkatopics
#
# NAME                     CLUSTER         PARTITIONS   REPLICATION FACTOR   READY
# reefer.telemetries       vaccine-kafka   3            3                    True
# test                     vaccine-kafka   1            1                    True
# vaccine.inventory        vaccine-kafka   1            1                    True
# vaccine.reefer           vaccine-kafka   1            1                    True
# vaccine.shipment.plans   vaccine-kafka   1            3                    True
# vaccine.transportation   vaccine-kafka   1            1                    True
```

### Deploy postgresql

```shell
oc apply -k environments/dev/infrastructure/postgres
```

## Deploy the different use cases

### Deploying Vaccine cold chain monitoring use case

Just run one of the following deploy scripts:

```shell
# For Strimzi
./scripts/deployColdChainWithStrimzi.sh --skip-login

# For event streams
./scripts/deployColdChainWithEventStreams.sh --skip-login
```

To delete the deployment

```shell
./scripts/deleleColdChain.sh
```

### Deploying order optimization use case

```shell
./scripts/deployOrderOptimWithEventStreams.sh --skip-login
```

This should deploy the optimization and order mgt.

```shell
oc get pods
# NAME                                   READY   STATUS      RESTARTS   AGE
# postgres-db-postgresql-0               1/1     Running     0          19h
# vaccine-transport-simulator-2-mcnnp    1/1     Running     0          3m37s
# vaccineorderms-2-2lctx                 1/1     Running     0          6m30s
```

To delete the deployment

```shell
./scripts/deleleOrderOptim.sh
```