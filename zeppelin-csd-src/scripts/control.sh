#!/bin/bash

set -ex

function log {
  timestamp=$(date)
  echo "$timestamp: $1"       #stdout
  echo "$timestamp: $1" 1>&2; #stderr
}

log "Running Zeppelin CSD control script..."
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
    # Set Zeppelin conf
    export ZEPPELIN_CONF_DIR="$CONF_DIR/zeppelin-conf"
    if [ ! -d "$ZEPPELIN_CONF_DIR" ]; then
      log "Could not find zeppelin-conf directory at $ZEPPELIN_CONF_DIR"
      exit 3
    fi
    # Set Livy conf
    export LIVY_CONF_DIR="$CONF_DIR/livy-conf"
    if [ ! -d "$LIVY_CONF_DIR" ]; then
      log "Could not find livy-conf directory at $LIVY_CONF_DIR"
      exit 3
    fi
    # Get livy url
    LIVY_CONF_FILE="$LIVY_CONF_DIR/server.properties"
    if [ ! -f "$LIVY_CONF_FILE" ]; then
       log "Cannot find livy config at $LIVY_CONF_FILE"
       exit 3
    fi
    # Build the LIVY URL, for now get the first host
    LIVY_HOSTNAME="$( sed 's#^\([^:]\+\):.*#\1#g' "$LIVY_CONF_FILE" | head -1 )"
    LIVY_SSL_ENABLED="$( grep "${LIVY_HOSTNAME}:livy\.ssl" "$LIVY_CONF_FILE" | sed 's#^.*livy\.ssl=\(.*\)#\1#g' | head -1 )"
    if [ "$LIVY_SSL_ENABLED" == "true" ]; then
      if [ -z "$ZEPPELIN_TRUSTSTORE" ]; then
        log "A truststore must be specified since Livy is using SSL"
        exit 6
      fi
      LIVY_PROTOCOL=https
    else
      LIVY_PROTOCOL=http
    fi
    LIVY_PORT="$( grep "${LIVY_HOSTNAME}:livy\.server\.port" "$LIVY_CONF_FILE" | sed 's#^.*livy\.server\.port=\(.*\)#\1#g' | head -1 )"
    LIVY_URL="${LIVY_PROTOCOL}://${LIVY_HOSTNAME}:${LIVY_PORT}"

    LIVY_INTERPRETER_CONF="$ZEPPELIN_CONF_DIR/interpreter.json"
    sed -i "s#{{LIVY_URL}}#$LIVY_URL#g" "$LIVY_INTERPRETER_CONF"
    sed -i "s#{{LIVY_PRINCIPAL}}#$ZEPPELIN_PRINCIPAL#g" "$LIVY_INTERPRETER_CONF"
    sed -i "s#{{LIVY_KEYTAB}}#zeppelin.keytab#g" "$LIVY_INTERPRETER_CONF"
    sed -i "s#{{DATA_DIR}}##g" "$ZEPPELIN_DATA_DIR"

    log "Starting the Zeppelin server"
    exec env ZEPPELIN_JAVA_OPTS="-Xms$ZEPPELIN_MEMORY -Xmx$ZEPPELIN_MEMORY" $ZEPPELIN_HOME/bin/zeppelin.sh
    ;;
  (*)
    echo "Don't understand [$1]"
    exit 1
    ;;
esac
