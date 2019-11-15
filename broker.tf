##
## Variables: these are the things that you can override on the command
## line, or using .tfvars files.
##

variable "do_token" {}						# Your Digital Ocean API access token

variable "num_brokers" {}                                       # Number of brokers in the Kafka cluster

variable "domain"   {}                                          # The domain name of the broker. The domain must be under Digital Ocean DNS control.
								# The default will create machines in the test domain; override on the command line
								# to create in the production domain.

##
## You should rarely need to override these:
##

variable "broker_size" { default = "s-6vcpu-16gb" }		# Digital Ocean instance type for the broker machine
variable "monitor_size" { default = "s-2vcpu-2gb" }		# Digital Ocean instance type for the monitor machine

variable "broker_hostname"  { default = "broker" }              # hostname of the broker
variable "monitor_hostname" { default = "status" }              # hostname of the monitor

#
# Fingerprint of the key to use for SSH-ing into the newly created machines.
# The key must be already uploaded to Digital Ocean via the web interface.
#
variable "ssh_fingerprint" { default = [ 
	"57:c0:dd:35:2a:06:67:d1:15:ba:6a:74:4d:7c:1c:21",
	"cd:78:d0:36:19:95:59:80:66:d9:e2:c9:39:52:80:c3",
	"37:70:f2:46:82:98:fc:a4:bf:d3:8c:38:1d:dd:b8:68"
] }

#################################################################################
#
# Compute useful local variables, set up DO provider, domain
#

locals {
  monitor_fqdn = "${var.monitor_hostname}.${var.domain}"
}

provider "digitalocean" {
  token = "${var.do_token}"
}

resource "digitalocean_domain" "default" {
   name = "${var.domain}"

   lifecycle {
     # This is to prevent accidentally destroying the whole (sub)domain; there
     # may be other entries in it that are not managed by terraform.
     prevent_destroy = true
   }
}

#################################################################################
#
#  The broker machine. Runs zookeeper, kafka, mirrormaker, and Prometheus
#  metrics exporters.
#
#################################################################################

resource "digitalocean_droplet" "broker" {
  image = "centos-7-x64"
  name = "${var.broker_hostname}${count.index}.${var.domain}"
  region = "sfo2"
  count = "${var.num_brokers}"
  size = "${var.broker_size}"
  private_networking = true
  ipv6 = true
  monitoring = true
  ssh_keys = [
    "${var.ssh_fingerprint}"
  ]
}

resource "digitalocean_record" "broker_pub" {
  depends_on = [ "digitalocean_droplet.broker" ]
  count = "${digitalocean_droplet.broker.count}"

  domain = "${digitalocean_domain.default.name}"
  type   = "A"
  name   = "ssh-${var.broker_hostname}${count.index}"
  value  = "${digitalocean_droplet.broker.*.ipv4_address[count.index]}"
  ttl    = "30"
}

resource "digitalocean_record" "broker_priv" {
  depends_on = [ "digitalocean_droplet.broker" ]
  count = "${digitalocean_droplet.broker.count}"

  domain = "${digitalocean_domain.default.name}"
  type   = "A"
  name   = "${var.broker_hostname}${count.index}"
  value  = "${digitalocean_droplet.broker.*.ipv4_address_private[count.index]}"
  ttl    = "30"
}

resource "digitalocean_record" "brokerAAAA" {
  domain = "${digitalocean_domain.default.name}"
  type   = "AAAA"
  name   = "${var.broker_hostname}"
  value  = "${digitalocean_droplet.broker.ipv6_address}"
  ttl    = "5"
}
