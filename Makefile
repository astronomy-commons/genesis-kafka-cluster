all:
	@echo Read the makefile for instructions on what to do.

cluster: tf-apply
	@echo Done creating. Now run 'make provision'

destroy: tf-destroy
	@echo Done

tf-apply:
	terraform apply --target digitalocean_record.broker_priv --target digitalocean_record.broker_pub
	ssh-keygen -R ssh-broker0.do.alerts.wtf
	ssh-keyscan -H ssh-broker0.do.alerts.wtf >> ~/.ssh/known_hosts

tf-destroy:
	terraform destroy --target digitalocean_droplet.broker

provision:
	ansible-playbook -i inventory site.yml

status:
	ssh root@ssh-broker0.do.alerts.wtf "kafkacat -L -b localhost"

### Developer utils

kafka:
	ansible-playbook -i inventory site.yml --tags kafka_broker
