# Modified by Santiago Bassett 19/06/2014

DESTDIR=/
DIR=$(DESTDIR)/var/ossec/
DIR_ETC=$(DESTDIR)/etc/
DIR_INIT=$(DESTDIR)/etc/init.d/
OSSEC_INIT=$(DESTDIR)/etc/ossec-init.conf
CEXTRA="-DCLIENT"
all:
	echo "CEXTRA=$(CEXTRA)" >> src/Config.OS
	(cd src; make all)	

clean:
	rm bin/* || /bin/true
	chmod 750 $(DIR) || /bin/true
	chmod 750 $(DIR)/* || /bin/true
	(cd src; make clean)
	rm -f src/Config.OS
	rm -f src/analysisd/compiled_rules/compiled_rules.h
	rm -f src/isbigendian.c
	rm -f src/analysisd/ossec-makelists
	rm -f src/analysisd/ossec-logtest
	rm -f src/isbigendian

install:
	mkdir -p $(DIR_ETC)
	mkdir -p $(DIR_INIT)
	cp -p src/init/ossec-hids.init $(DIR_INIT)/ossec
	mkdir -p $(DIR)
	(cd $(DIR); mkdir -p logs bin queue queue/ossec queue/alerts queue/syscheck queue/diff queue/rids) 
	(cd $(DIR); mkdir -p var var/run etc etc/shared active-response active-response/bin agentless .ssh)
	cp -pr src/rootcheck/db/*.txt $(DIR)/etc/shared/
	chmod -x $(DIR)/etc/shared/*.txt
	cp -pr etc/internal_options.conf $(DIR)/etc/
	chmod -x $(DIR)/etc/internal_options.conf
	cp -pr etc/local_internal_options.conf $(DIR)/etc/ > /dev/null 2>&1 || /bin/true
	cp -pr etc/client.keys $(DIR)/etc/ > /dev/null 2>&1 ||/bin/true
	cp -pr src/agentlessd/scripts/* $(DIR)/agentless/
	cp -pr src/client-agent/ossec-agentd ${DIR}/bin/
	cp -pr src/os_auth/agent-auth ${DIR}/bin/
	cp -pr src/logcollector/ossec-logcollector ${DIR}/bin/
	cp -pr src/syscheckd/ossec-syscheckd ${DIR}/bin/
	cp -pr src/os_execd/ossec-execd ${DIR}/bin/
	cp -pr src/init/ossec-client.sh ${DIR}/bin/ossec-control
	cp -pr src/addagent/manage_agents ${DIR}/bin/
	cp -pr contrib/util.sh ${DIR}/bin/
	sh src/init/fw-check.sh execute > /dev/null
	cp -pr active-response/*.sh ${DIR}/active-response/bin/
	cp -pr active-response/firewalls/*.sh ${DIR}/active-response/bin/
	cp -pr etc/ossec-agent.conf $(DIR)/etc/ossec.conf
	chmod -x $(DIR)/etc/ossec.conf
	echo "DIRECTORY=\"/var/ossec\"" > $(OSSEC_INIT)
	echo "VERSION=\"v2.8\"" >> $(OSSEC_INIT)
	echo "DATE=\"`date`\"" >> $(OSSEC_INIT)
	echo "TYPE=\"server\"" >> $(OSSEC_INIT)
