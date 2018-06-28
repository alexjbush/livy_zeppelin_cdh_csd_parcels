#!/bin/bash

set -ex

function log {
  timestamp=$(date)
  echo "$timestamp: $1"       #stdout
  echo "$timestamp: $1" 1>&2; #stderr
}

log "Running Livy CSD control script..."
log "Detected CDH_VERSION of [$CDH_VERSION]"
log "Got command as $1"

case $1 in
  (start)
    # Set java path
    if [ -n "$JAVA_HOME" ]; then
      log "JAVA_HOME added to path as $JAVA_HOME"
      export PATH=$JAVA_HOME/bin:$PATH
    else
      log "JAVA_HOME not set"
    fi
    # Set Spark and Hadoop home and Hadoop conf
    if [ "$LIVY_SPARK_VERSION" == "spark" ]; then
      if [ ! -d "$CDH_SPARK_HOME" ]; then
        log "Cannot find Spark home at: $CDH_SPARK_HOME"
        exit 2
      fi
      export SPARK_HOME=$CDH_SPARK_HOME
    elif [ "$LIVY_SPARK_VERSION" == "spark2" ]; then
      if [ ! -d "$CDH_SPARK2_HOME" ]; then
        log "Cannot find Spark2 home at: $CDH_SPARK2_HOME"
        exit 2
      fi
      export SPARK_HOME=$CDH_SPARK2_HOME
    else
      log "Cannot recognise spark version: $LIVY_SPARK_VERSION"
    fi
    export HADOOP_HOME=${HADOOP_HOME:-$(readlink -m "$CDH_HADOOP_HOME")}
    # Set Hadoop config dir. If hive context is enabled this will be hive-conf since this
    # contains hive-site, hdfs-site, yarn-site and core-site
    if [ "$HIVE_CONTEXT_ENABLE" == "true" ]; then
      if [ -d "$CONF_DIR/hive-conf" ]; then
        export HADOOP_CONF_DIR="$CONF_DIR/hive-conf"
      else
        log "Could not find a hive-site at: $HIVE_SITE"
        exit 5
      fi
    elif [ -d "$CONF_DIR/yarn-conf" ]; then
      export HADOOP_CONF_DIR="$CONF_DIR/yarn-conf"
    elif [ -d "$CONF_DIR/hadoop-conf" ]; then
      export HADOOP_CONF_DIR="$CONF_DIR/hadoop-conf"
    else
      log "Could not find a yarn/hadoop conf directory at $CONF_DIR/yarn-conf or $CONF_DIR/hadoop-conf"
      exit 2
    fi
    # Copy hive-site to hadoop dir
    # Set Livy conf
    export LIVY_CONF_DIR="$CONF_DIR/%SERVICENAMELOWER%-conf"
    if [ ! -d "$LIVY_CONF_DIR" ]; then
      log "Could not find %SERVICENAMELOWER%-conf directory at $LIVY_CONF_DIR"
      exit 3
    fi
    # Update Livy conf for Kerberos and ssl
    CONF_FILE="$LIVY_CONF_DIR/livy.conf"
    if [ ! -f "$CONF_FILE" ]; then
       log "Cannot find livy config at $CONF_FILE"
       exit 3
    fi
    # Config for SSL
    if [ "$SSL_ENABLED" == "true" ]; then
       echo "livy.keystore=$KEYSTORE_LOCATION" >> "$CONF_FILE"
       echo "livy.keystore.password=$KEYSTORE_PASSWORD" >> "$CONF_FILE"
       echo "livy.keystore.keypassword=$KEYSTORE_KEYPASSWORD" >> "$CONF_FILE"
    fi
    if [ "$LIVY_PRINCIPAL" != "" ]; then
       echo "livy.server.launch.kerberos.principal=$LIVY_PRINCIPAL" >> "$CONF_FILE"
       echo "livy.server.launch.kerberos.keytab=livy.keytab" >> "$CONF_FILE"
       #SPNEGO config
       if [ "$ENABLE_SPNEGO" = "true" ] && [ -n "$SPNEGO_PRINCIPAL" ]; then
         echo "livy.server.auth.type=kerberos" >> "$CONF_FILE"
         echo "livy.server.auth.kerberos.principal=$SPNEGO_PRINCIPAL" >> "$CONF_FILE"
         echo "livy.server.auth.kerberos.keytab=livy.keytab" >> "$CONF_FILE"
         echo "livy.superusers=$LIVY_SUPERUSERS" >> "$CONF_FILE"
         if [ "$ENABLE_ACCESS_CONTROL" == "true" ]; then
           echo "livy.server.access-control.enabled=true" >> "$CONF_FILE"
           echo "livy.server.access-control.users=$ACCESS_CONTROL_USERS" >> "$CONF_FILE"
         fi
       fi
    fi
    echo "Starting the Livy server"
    exec env LIVY_SERVER_JAVA_OPTS="-Divy.home=${IVY_DATA_DIR} -Xms$LIVY_MEMORY -Xmx$LIVY_MEMORY" CLASSPATH=`hadoop classpath` $LIVY_HOME/bin/livy-server
    ;;
  (*)
    echo "Don't understand [$1]"
    exit 1
    ;;
esac
