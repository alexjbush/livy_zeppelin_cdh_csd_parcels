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
    export SPARK_HOME=$CDH_SPARK_HOME
    export HADOOP_HOME=${HADOOP_HOME:-$(readlink -m "$CDH_HADOOP_HOME")}
    if [ -d "$CONF_DIR/yarn-conf" ]; then
      HADOOP_CONF_DIR="$CONF_DIR/yarn-conf"
    elif [ -d "$CONF_DIR/hadoop-conf" ]; then
      HADOOP_CONF_DIR="$CONF_DIR/hadoop-conf"
    else
      log "Could not find a yarn/hadoop conf directory at $CONF_DIR/yarn-conf or $CONF_DIR/hadoop-conf"
      exit 2
    fi
    # Set Livy conf
    export LIVY_CONF_DIR="$CONF_DIR/livy-conf"
    if [ ! -d "$LIVY_CONF_DIR" ]; then
      mkdir "$LIVY_CONF_DIR"
      log "Could not find livy-conf directory at $LIVY_CONF_DIR"
      exit 3
    fi
    # Update Livy conf for Kerberos
    CONF_FILE="$LIVY_CONF_DIR/livy.conf"
    if [ "$LIVY_PRINCIPAL" != "" ]; then
       echo "livy.server.auth.type=kerberos" >> "$CONF_FILE"
       echo "livy.server.launch.kerberos.principal=$LIVY_PRINCIPAL" >> "$CONF_FILE"
       echo "livy.server.launch.kerberos.keytab=livy.keytab" >> "$CONF_FILE"
       #SPNEGO config
       if [ "$ENABLE_SPNEGO" = "true" ] && [ -n "$SPNEGO_PRINCIPAL" ]; then
         echo "livy.server.auth.kerberos.principal=$SPNEGO_PRINCIPAL" >> "$CONF_FILE"
         echo "livy.server.auth.kerberos.keytab=livy.keytab" >> "$CONF_FILE"
         echo "livy.superusers=$LIVY_SUPERUSERS" >> "$CONF_FILE"
         if [ "$ENABLE_ACCESS_CONTROL" == "true" ]; then
           echo "livy.server.access_control.enabled=true" >> "$CONF_FILE"
           echo "livy.server.access_control.users=$ACCESS_CONTROL_USERS" >> "$CONF_FILE"
         fi
       fi
    fi
    echo "Starting the Livy server"
    exec env LIVY_SERVER_JAVA_OPTS="-Xms$LIVY_MEMORY -Xmx$LIVY_MEMORY" CLASSPATH=`hadoop classpath` $LIVY_HOME/bin/livy-server
    ;;
  (*)
    echo "Don't understand [$1]"
    exit 1
    ;;
esac
