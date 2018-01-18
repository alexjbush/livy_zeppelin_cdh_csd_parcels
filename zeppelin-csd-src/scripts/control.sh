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

    LIVY_INTERPRETER_CONF="$ZEPPELIN_CONF_DIR/interpreter.json"
    function get_livy_url {
        LIVY_HOSTNAME="$( grep "$1\$" "$LIVY_CONF_FILE" | sed 's#^\([^:]\+\):.*#\1#g' | head -1 )"
        if [ -z "$LIVY_HOSTNAME" ]; then
          # Spark version not found
          return
        fi
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
        echo "$LIVY_URL"
        return
    }
    function spark_interpreter {
      SPARK_VERSION="$1" #spark or spark2
      INTERPRETER_ID="$2" # some ID like 2CZ9EX8ZX
      INTERPRETER_NAME="$3" # some name like livy or livy2
      LIVY_URL="$( get_livy_url "$SPARK_VERSION" )"
      if [ -z "$LIVY_URL" ]; then
        log "No endpoint for $SPARK_VERSION, skipping interpreter setup"
        sed -i "s#{{INTERPRETER_BINDING_$SPARK_VERSION}}##g" "$LIVY_INTERPRETER_CONF"
        sed -i "s#{{SPARK_CONFIG_$SPARK_VERSION}}##g" "$LIVY_INTERPRETER_CONF"
      else
        LIVY_TEMP_CONF="$ZEPPELIN_CONF_DIR/interpreter.livy.json.$SPARK_VERSION"
        cp "$ZEPPELIN_CONF_DIR/interpreter.livy.json" "$LIVY_TEMP_CONF"
        sed -i "s#{{EXECUTOR_MEMORY}}#$EXECUTOR_MEMORY#g" "$LIVY_TEMP_CONF"
        sed -i "s#{{MAX_EXECUTORS}}#$MAX_EXECUTORS#g" "$LIVY_TEMP_CONF"
        sed -i "s#{{DRIVER_MEMORY}}#$DRIVER_MEMORY#g" "$LIVY_TEMP_CONF"
        sed -i "s#{{LIVY_URL}}#$LIVY_URL#g" "$LIVY_TEMP_CONF"
        sed -i "s#{{LIVY_PRINCIPAL}}#$ZEPPELIN_PRINCIPAL#g" "$LIVY_TEMP_CONF"
        sed -i "s#{{LIVY_KEYTAB}}#zeppelin.keytab#g" "$LIVY_TEMP_CONF"
        sed -i "s#{{DATA_DIR}}#$ZEPPELIN_DATA_DIR#g" "$LIVY_TEMP_CONF"
        sed -i "s#{{INTERPRETER_NAME}}#$INTERPRETER_NAME#g" "$LIVY_TEMP_CONF"
        sed -i "s#{{INTERPRETER_ID}}#$INTERPRETER_ID#g" "$LIVY_TEMP_CONF"
        sed -i "s#{{LIVY_SPARK_JARS_PACKAGES}}#$LIVY_SPARK_JARS_PACKAGES#g" "$LIVY_TEMP_CONF"
        sed -i "s#{{LIVY_SPARK_JARS}}#$LIVY_SPARK_JARS#g" "$LIVY_TEMP_CONF"
        sed -e "/{{SPARK_CONFIG_$SPARK_VERSION}}/ {" -e "r $LIVY_TEMP_CONF" -e 'd' -e '}' -i "$LIVY_INTERPRETER_CONF"
        sed -i "s#{{INTERPRETER_BINDING_$SPARK_VERSION}}#\"$INTERPRETER_ID\",#g" "$LIVY_INTERPRETER_CONF"
      fi
    }
    spark_interpreter "spark" "2CYCWRZPP" "livy"
    spark_interpreter "spark2" "2CYCWDZPP" "livy2"
    sed -i "s#{{INTERPRETER_FOR_NOTE}}#$INTERPRETER_FOR_NOTE#g" "$LIVY_INTERPRETER_CONF"
    sed -i "s#{{INTERPRETER_FOR_USER}}#$INTERPRETER_FOR_USER#g" "$LIVY_INTERPRETER_CONF"
    SHIRO_CONF="$ZEPPELIN_CONF_DIR/shiro.ini"
    if [ "$ZEPPELIN_SHIRO_ENABLED" == "false" ]; then
      mv "$SHIRO_CONF" "${SHIRO_CONF}.template"
    fi
    #Add link to interpreter permissions so it is maintained between restarts
    ln -s "${ZEPPELIN_DATA_DIR}/notebook-authorization.json" "${ZEPPELIN_CONF_DIR}/notebook-authorization.json"

    log "Starting the Zeppelin server"
    exec env ZEPPELIN_JAVA_OPTS="-Xms$ZEPPELIN_MEMORY -Xmx$ZEPPELIN_MEMORY" $ZEPPELIN_HOME/bin/zeppelin.sh
    ;;
  (*)
    echo "Don't understand [$1]"
    exit 1
    ;;
esac
