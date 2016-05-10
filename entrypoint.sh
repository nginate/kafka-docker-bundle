#!/usr/bin/env bash

# Optional ENV variables:
# * ADVERTISED_HOST: the external ip for the container, e.g. `docker-machine ip \`docker-machine active\``
# * ADVERTISED_PORT: the external port for Kafka, e.g. 9092
# * ZK_CHROOT: the zookeeper chroot that's used by Kafka (without / prefix), e.g. "kafka"
# * LOG_RETENTION_HOURS: the minimum age of a log file in hours to be eligible for deletion (default is 168, for 1 week)
# * LOG_RETENTION_BYTES: configure the size at which segments are pruned from the log, (default is 1073741824, for 1GB)
# * NUM_PARTITIONS: configure the default number of log partitions per topic

set -e

log(){
    echo -e "`date`\t$@"
}

replace_placeholder() {
    log "Changing $1 to $2 in $3 with s|\{$1\}|$2|"
    sed -ri "s|\{$1\}|$2|" $3
}

[[ $1 == *"kafka"* ]] && {

    # Configure advertised host/port if we run in helios
    [[ ! -z "$HELIOS_PORT_kafka" ]] && {
        ADVERTISED_HOST=`echo ${HELIOS_PORT_kafka} | cut -d':' -f 1 | xargs -n 1 dig +short | tail -n 1`
        ADVERTISED_PORT=`echo ${HELIOS_PORT_kafka} | cut -d':' -f 2`
    }

    # Set the external host and port
    [[ ! -z "$ADVERTISED_HOST" ]] && {
        log "advertised host: $ADVERTISED_HOST"
        sed -r -i "s/#(advertised.host.name)=(.*)/\1=$ADVERTISED_HOST/g" ${KAFKA_HOME}/config/server.properties
    }
    [[ ! -z "$ADVERTISED_PORT" ]] && {
        log "advertised port: $ADVERTISED_PORT"
        sed -r -i "s/#(advertised.port)=(.*)/\1=$ADVERTISED_PORT/g" ${KAFKA_HOME}/config/server.properties
    }

    # Starting zookeeper
    /usr/share/zookeeper/bin/zkServer.sh start-foreground &
    # wait for zookeeper to start up
    until /usr/share/zookeeper/bin/zkServer.sh status; do
        sleep 0.1
    done
    # Set the zookeeper chroot
    [[ ! -z "$ZK_CHROOT" ]] && {
        # create the chroot node
        echo "create /$ZK_CHROOT \"\"" | /usr/share/zookeeper/bin/zkCli.sh || {
            echo "can't create chroot in zookeeper, exit"
            exit 1
        }
        sed -r -i "s/(zookeeper.connect)=(.*)/\1=localhost:2181\/$ZK_CHROOT/g" ${KAFKA_HOME}/config/server.properties
    } || {
        # configure kafka
        sed -r -i "s/(zookeeper.connect)=(.*)/\1=localhost:2181/g" ${KAFKA_HOME}/config/server.properties
    }

    # Setting default log level for kafka
    log "default log level: $KAFKA_LOGLEVEL"
    sed -r -i "s/(log4j.rootLogger)=(\w+)/\1=$KAFKA_LOGLEVEL/g" ${KAFKA_HOME}/config/log4j.properties


    # Allow specification of log retention policies
    [[ ! -z "$LOG_RETENTION_HOURS" ]] && {
        log "log retention hours: $LOG_RETENTION_HOURS"
        sed -r -i "s/(log.retention.hours)=(.*)/\1=$LOG_RETENTION_HOURS/g" ${KAFKA_HOME}/config/server.properties
    }
    [[ ! -z "$LOG_RETENTION_BYTES" ]] && {
        log "log retention bytes: $LOG_RETENTION_BYTES"
        sed -r -i "s/#(log.retention.bytes)=(.*)/\1=$LOG_RETENTION_BYTES/g" ${KAFKA_HOME}/config/server.properties
    }

    # Configure the default number of log partitions per topic
    log "default number of partition: $NUM_PARTITIONS"
    sed -r -i "s/(num.partitions)=(.*)/\1=$NUM_PARTITIONS/g" ${KAFKA_HOME}/config/server.properties

    # Configure Kafka startup port
    log "kafka port: $KAFKA_PORT"
    replace_placeholder "port" ${KAFKA_PORT} "${KAFKA_HOME}/config/server.properties"

    # Enable/disable auto creation of topics
    [[ ! -z "$AUTO_CREATE_TOPICS" ]] && {
        log "auto.create.topics.enable: $AUTO_CREATE_TOPICS"
        echo "auto.create.topics.enable=$AUTO_CREATE_TOPICS" >> ${KAFKA_HOME}/config/server.properties
    }

    log "offsets.topic.replication.factor : ${REPLICATION_FACTOR}"
    echo "offsets.topic.replication.factor=$REPLICATION_FACTOR" >> ${KAFKA_HOME}/config/server.properties

    log "leader.imbalance.check.interval.seconds : ${LEADER_REBALANCE_CHECK_INTERVAL}"
    echo "leader.imbalance.check.interval.seconds=$LEADER_REBALANCE_CHECK_INTERVAL" >> ${KAFKA_HOME}/config/server.properties

    # Capture kill requests to stop properly
    trap "${KAFKA_HOME}/bin/kafka-server-stop.sh; echo 'Kafka stopped.'; exit" SIGHUP SIGINT SIGTERM
    trap "/usr/share/zookeeper/bin/zkServer.sh stop; echo 'zookeeper stopped.'; exit" SIGHUP SIGINT SIGTERM

    set -- "${KAFKA_HOME}/bin/kafka-server-start.sh" "${KAFKA_HOME}/config/server.properties"
}

log "Executing $@"
exec $@
