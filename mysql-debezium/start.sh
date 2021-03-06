#!/bin/bash

# Source library
. ../utils/helper.sh

check_env || exit 1
check_running_cp 4.1 || exit 
check_mysql || exit
check_running_elasticsearch 5.6.5 || exit 1
check_running_kibana || exit 1

./stop.sh

get_ksql_ui
# Add Debezium connector
mkdir -p $CONFLUENT_HOME/share/java/debezium-connector-mysql
cp -nR ./debezium-connector-mysql/* $CONFLUENT_HOME/share/java/debezium-connector-mysql/.
confluent start

# MySQL: Drop & repopulate data
echo "CREATE DATABASE IF NOT EXISTS demo;" | mysql -uroot
mysql demo -uroot < customers.sql
echo "GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'debezium@localhost' IDENTIFIED BY 'dbz';" | mysql -uroot

# Source Kafka connectors
confluent config mysql-source-demo-customers -d ./connector_debezium_customers.config
confluent config mysql-source-demo-customers-raw -d ./connector_debezium_customers-raw.config
sleep 10

if is_ce; then PROPERTIES=" propertiesFile=$CONFLUENT_HOME/etc/ksql/datagen.properties"; else PROPERTIES=""; fi
ksql-datagen quickstart=ratings format=avro topic=ratings maxInterval=500 $PROPERTIES &>/dev/null &
sleep 10

ksql http://localhost:8088 <<EOF
run script 'ksql.commands';
exit ;
EOF

./dashboard/set_elasticsearch_mapping.sh 
./dashboard/configure_kibana_objects.sh

# Sink Kafka connector
confluent config es_sink_RATINGS_ENRICHED -d ./connector_elasticsearch.config
