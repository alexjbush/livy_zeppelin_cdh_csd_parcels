#!/usr/bin/python
import ConfigParser
import StringIO
import json
import sys, datetime, os

import shutil


def log(msg):
    msg_with_ts = "%s: %s" % (datetime.datetime.now(), msg)
    print >> sys.stderr, msg_with_ts
    print msg_with_ts


def error_if_missing(path):
    if not os.path.exists(path):
        log("ERROR: Path does not exist: %s" % path)
        sys.exit(1)


def properties_string_to_dict(prop_string):
    ini_str = '[dummy]\n' + prop_string
    ini_fp = StringIO.StringIO(ini_str)
    config = ConfigParser.RawConfigParser()
    config.optionxform = str
    config.readfp(ini_fp)
    return {k: v for k, v in config.items("dummy")}


def read_file(filename):
    with open(filename, 'r') as openfile:
        return openfile.read()


def get_livy_details(prop_string, spark_service_name):
    maybe_hostname = [line.split(":")[0] for line in prop_string.splitlines() if
                      line.endswith("spark.version=%s" % spark_service_name)]
    if len(maybe_hostname) == 0:
        return None
    hostname = maybe_hostname[0]
    res = {}
    for line in prop_string.splitlines():
        if line.startswith(hostname):
            trimmed = line.split(":")[1]
            kv = trimmed.split("=")
            res[kv[0]] = kv[1]
    res["livy.server.hostname"] = hostname
    return res


def get_livy_url(livy_dict):
    if livy_dict["livy.ssl"] == "true":
        if "ZEPPELIN_TRUSTSTORE" not in os.environ.keys():
            log("A truststore must be specified since Livy is using SSL")
            sys.exit(1)
        else:
            livy_protocol = "https"
    else:
        livy_protocol = "http"
    return "%s://%s:%s" % (livy_protocol, livy_dict["livy.server.hostname"], livy_dict['livy.server.port'])


def generate_livy_conf_struct(spark_version, interpreter_id, interpreter_name, livy_server_properties, interpreter_json,
                              interpreter_properties_string):
    livy_dict = get_livy_details(livy_server_properties, spark_version)
    if livy_dict is None:
        return None
    livy_url = get_livy_url(livy_dict)
    conf = json.loads(interpreter_json)
    conf["option"]["perNote"] = os.environ["INTERPRETER_FOR_NOTE"]
    conf["option"]["perUser"] = os.environ["INTERPRETER_FOR_USER"]
    conf["id"] = interpreter_id
    conf["name"] = interpreter_name
    conf["properties"]["zeppelin.livy.url"] = livy_url
    conf["properties"]["zeppelin.interpreter.localRepo"] = "%s/local-repo/%s" % (os.environ["ZEPPELIN_DATA_DIR"], interpreter_id)
    if "ZEPPELIN_PRINCIPAL" in os.environ.keys():
        conf["properties"]["zeppelin.livy.principal"] = os.environ["ZEPPELIN_PRINCIPAL"]
        conf["properties"]["zeppelin.livy.keytab"] = "%SERVICENAMELOWER%.keytab"
    props = properties_string_to_dict(interpreter_properties_string)
    for k, v in props.iteritems():
        conf["properties"][k] = v
    return conf


def merge_livy_confs_into_interpreter(interpreter_string, livy_interpreters):
    interpreter = json.loads(interpreter_string)
    for livy in livy_interpreters:
        id = livy["id"]
        interpreter["interpreterSettings"][id] = livy
        interpreter["interpreterBindings"]["2CYUMWD38"].append(id)
    return interpreter


def run_command(command):
    log("Running command: %s" % command)
    rt = os.system(command)
    if rt != 0:
        log("Non-zero error code running command: %s" % command)
        sys.exit(1)


def base_conf():
    log("Detected CDH_VERSION of [%s]" % os.environ["CDH_VERSION"])

    # Set java path
    if "JAVA_HOME" in os.environ.keys():
        log("JAVA_HOME added to path as %s" % os.environ["JAVA_HOME"])
        os.environ["PATH"] = "%s:%s" % (os.environ["JAVA_HOME"], os.environ["PATH"])
    else:
        log("JAVA_HOME not set")

    # Zeppelin java opts
    os.environ["ZEPPELIN_JAVA_OPTS"] = "%s -Xms%s -Xmx%s" % (
        os.environ["ZEPPELIN_EXTRA_JAVA_OPTIONS"],
        os.environ["ZEPPELIN_MEMORY"], os.environ["ZEPPELIN_MEMORY"])

    # Check and set various conf directories
    base_conf_dir = os.environ["CONF_DIR"]
    zeppelin_conf_dir = "%s/%SERVICENAMELOWER%-conf" % base_conf_dir
    error_if_missing(zeppelin_conf_dir)
    os.environ["ZEPPELIN_CONF_DIR"] = zeppelin_conf_dir
    os.environ["ZEPPELIN_PID_DIR"] = "%s/run" % os.environ["ZEPPELIN_LOG_DIR"]
    os.environ["ZEPPELIN_IDENT_STRING"] = "zeppelin"
    return (base_conf_dir, zeppelin_conf_dir)

def start():
    log("Attempting to start")

    # Base config
    (base_conf_dir, zeppelin_conf_dir) = base_conf()

    #Start specific conf
    livy_conf_dir = "%s/%LIVYSERVICENAMELOWER%-conf" % base_conf_dir
    error_if_missing(livy_conf_dir)
    livy_conf_file = "%s/server.properties" % livy_conf_dir
    error_if_missing(livy_conf_file)
    server_props_string = read_file(livy_conf_file)
    livy_interpreter_json_filename = "%s/interpreter.livy.json" % zeppelin_conf_dir
    error_if_missing(livy_interpreter_json_filename)
    livy_interpreter_json_string = read_file(livy_interpreter_json_filename)
    livy_properties_filename = "%s/livy.properties" % zeppelin_conf_dir
    error_if_missing(livy_properties_filename)
    livy_properties_string = read_file(livy_properties_filename)

    livy_conf_struct = generate_livy_conf_struct("spark", "2CYCWRZPP", "livy", server_props_string,
                                                 livy_interpreter_json_string, livy_properties_string)
    livy2_conf_struct = generate_livy_conf_struct("spark2", "2CYCWDZPP", "livy2", server_props_string,
                                                  livy_interpreter_json_string, livy_properties_string)

    livy_interpreters = []
    if livy_conf_struct is not None:
        livy_interpreters.append(livy_conf_struct)
    if livy2_conf_struct is not None:
        livy_interpreters.append(livy2_conf_struct)

    interpreter_json_filename = "%s/interpreter.json" % zeppelin_conf_dir
    error_if_missing(interpreter_json_filename)
    interpreter_string = read_file(interpreter_json_filename)

    interpreter_struct = merge_livy_confs_into_interpreter(interpreter_string, livy_interpreters)
    completed_filename = "%s/interpreter.json" % zeppelin_conf_dir
    with open(completed_filename, 'w+') as f:
        json.dump(interpreter_struct, f)

    run_command("hdfs dfs -mkdir -p %s" % (os.environ["ZEPPELIN_CONF_FS_DIR"]))

    run_command("hdfs dfs -put -f %s %s" % (completed_filename, os.environ["ZEPPELIN_CONF_FS_DIR"]))

    run_command("hdfs dfs -mkdir -p %s" % (os.environ["ZEPPELIN_NOTEBOOK_DIR"]))

    shiro_filename = "%s/shiro.ini" % zeppelin_conf_dir
    error_if_missing(interpreter_json_filename)
    if os.environ["ZEPPELIN_SHIRO_ENABLED"] == "false":
        shutil.move(shiro_filename, "%s.template" % shiro_filename)

    #Run zeppelin, this seems to leak threads, look for a way to clean up properly
    run_command("%s/bin/zeppelin-daemon.sh --config %s start" % (os.environ["ZEPPELIN_HOME"], os.environ["ZEPPELIN_CONF_DIR"]))

    #Wait for PID to stop
    run_command("tail --pid=$( cat %s/zeppelin-zeppelin-*.pid) -f /dev/null" % os.environ["ZEPPELIN_PID_DIR"])
    return

def stop():
    log("Attempting to stop")

    # Base config
    (base_conf_dir, zeppelin_conf_dir) = base_conf()

    run_command("%s/bin/zeppelin-daemon.sh --config %s stop" % (os.environ["ZEPPELIN_HOME"], os.environ["ZEPPELIN_CONF_DIR"]))
    return

if __name__ == '__main__':
    log("Running Zeppelin CSD control script...")

    if len(sys.argv) < 2:
        log("No argument given")
        sys.exit(1)
    elif sys.argv[1] == "start":
        start()
    elif sys.argv[1] == "stop":
        stop()
    else:
        log("Don't understand [%s]" % sys.argv[1])
