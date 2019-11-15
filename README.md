# Scripts to Stand Up a Demo Kafka Cluster

## Introduction

This is a collection of Terraform scripts and Ansible playbooks needed to
stand up a zookeeper+kafka cluster on Digital Ocean, suitable for
development and demonstration purposes. It is based on the [ZADS
deployment scripts](https://github.com/dirac-institute/zads-terraform), with
cluster operation and provisioning via Ansible being the key difference.

## Description of the deployed cluster

* The base operating system is CentOS 7.

* The scripts create a cluster of `$NUM_BROKERS` (default: 4) kafka brokers,
  with a zookeeper running at each broker. This can be overridden by
  editing the `settings.auto.tfvars` file.

* All machines in the cluster have a public (`eth0`) and private (`eth1`)
  network interface.  Both Zookeeper and Kafka brokers are configured to
  communicate only on the private interface only (thus avoiding network
  bandwith charges).  We recommend a science platform (e.g., JupyterHub on
  k8s) be deployed within the same Digital Ocean project, to allow access to
  the broker through the private interface.

* All Kafka instances export Prometheus-compatible JMX metrics on port 8080.

* The DNS names of the machines are `brokerN.do.alerts.wtf` (private) and
  `ssh-brokerN.do.alerts.wtf` (public interface), with `N` being an ID
  running from `0` to `$NUM_BROKERS-1`. As indicated by the name, the public
  DNS names are largely for ssh access while debugging.

* The default replication factor is 2, and default number of partitions is
  16.  Partitions are lz4-compressed by default.  Messages are retained for
  1 day by default, and offsets for 2 days (1440 minutes).  Edit
  `inventory/hosts.yml` to customize.

* The first broker (`broker0`) comes with one night of ZTF alerts
  preinstalled, and an ingestion script that you can run to simulate nightly
  observations. See below for how to use it.

* ***WARNING: There is no authentication or authorization.*** Anyone can create or delete
  topics. Do not deploy this w/o a firewall or for production.

* Default firewall configuration blocks everything but `ssh` on the public
  interface. The private interface is fully trusted (no firewalling).

## Prerequisites

* You will need Ansible, Terraform, jq, and a Digital Ocean account.  Assuming
  you're using `brew` as your package manager, run:

  ```
  brew install terraform
  brew install ansible
  brew install jq
  ```
  to install the tools.

  You will also need these Ansible roles and plugins:

  ```
  ansible-galaxy install andrewrothstein.miniconda

  mkdir -p ~/.ansible/plugins/modules
  curl -o ~/.ansible/plugins/modules/conda.py https://raw.githubusercontent.com/UDST/ansible-conda/master/conda.py
  ```

* Next, you will need Confluent's Ansible playbooks for Kafka:

  ```
  git clone git@github.com:confluentinc/cp-ansible
  ```
  (make sure you run this in the current directory; the Makefile expects it
  there).

  * You'll need a Digital Ocean [personal access token](https://www.digitalocean.com/community/tutorials/how-to-use-the-digitalocean-api-v2),
  stored in `do_token.auto.tfvars` as follows:
  ```
  $ cat do_token.auto.tfvars
  do_token = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
  ```

* You will need an SSH key (registered with Digital Ocean) which will be
  authorized to log into the newly created nodes. Specify the MD5 fingerprint
  of the key in the `settings.auto.tfvars` file (it's the fingerprint show in
  DO's [Account|Security](https://cloud.digitalocean.com/account/security) tab).

* Finaly, your Digital Ocean account will have to host a [DNS
  domain](https://cloud.digitalocean.com/networking/domains) within which all
  created brokers will live. The default domain is `do.alerts.wtf` -- make
  sure you replace it with your own by adding it to `settings.auto.tfvars`.

### Customization

Basic customization is possible through the `settings.auto.tfvars` file:
```
$ cat settings.auto.tfvars
num_brokers = 4
domain = "do.alerts.wtf"
ssh_fingerprint = [ "57:c0:dd:35:2a:06:67:d1:15:ba:6a:74:4d:7c:1c:21" ]
```

For detailed customization of broker configuration, etc., edit the variables
in the Ansible inventory file in `inventory/hosts.yml`.

## Creating a cluster

First, make sure you have all the prerequisites installed (see above). Then run:

```
# Initialize terraform
terraform init

# Import the information about the domain where the hosts will reside
terraform import digitalocean_domain.default do.alerts.wtf

# Create the VMs (using terraform)
make cluster

# Provision the VMs (using ansible)
make provision
```

Once the VMs are created and provisioned, a Kafka should be running at
`brokerN.do.alerts.wtf:9092` (note: these are all *private* interfaces,
inaccessible from the outside).

## Testing

One night of ZTF alerts will be uploaded to `broker0:/root/alerts`, together
with an injection script which can inject batches of alerts onto topics to
simulate survey-like operation.

For example, to inject 10000 alerts every 40 seconds to a topic named
`lsst`, from the `/root/alerts` directory on `broker0` run:

```
[root@broker0 alerts]# ../inject.sh lsst 40 10000
Preparing chunks (10000 alerts each)... done (28 chunks).
[Thu Nov 14 16:43:59 PST 2019] injecting tmp-visit.aa to lsst ... done (6 seconds)
[Thu Nov 14 16:44:39 PST 2019] injecting tmp-visit.ab to lsst ... done (6 seconds)
```
(hit CTRL-C to stop).

You should be able to see that alerts are being injected using (e.g.)
`kt`:
```
[root@broker0 alerts]# kt topic -partitions -filter 'lsst' | jq -r '.name as $name | .partitions[] | [$name, .id, .oldest, .newest] | @tsv' | sort
lsst	0	0	1040
lsst	10	0	1285
lsst	1	0	1263
lsst	11	0	1169
lsst	12	0	1248
lsst	13	0	1371
lsst	14	0	1326
lsst	15	0	1257
lsst	2	0	1301
lsst	3	0	1158
lsst	4	0	1254
lsst	5	0	1407
lsst	6	0	1349
lsst	7	0	1246
lsst	8	0	1086
lsst	9	0	1240
```
(where the topic contents have been broken out by partition).

For the total number of alerts in a topic, run:
```
[root@broker0 alerts]# kt topic -partitions -filter 'lsst' | jq -r '.name as $name | .partitions[] | [$name, .id, .oldest, .newest] | @tsv' | awk '{a[$1]+=$4-$3} END {for(i in a) print i"\t"a[i]}' | sort
lsst	20000
```

## Destroying the cluster

To destroy an existing cluster, run:
```
make destroy
```
