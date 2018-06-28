#!/bin/bash
set -x
set -e

CM_EXT_BRANCH=cm5-5.12.0
LIVY_URL=http://apache.mirror.anlx.net/incubator/livy/0.5.0-incubating/livy-0.5.0-incubating-bin.zip
LIVY_MD5="cc9dc5518e8c178808707eaa68b7672a"
LIVY_VERSION=0.5.0

ZEPPELIN_URL=http://apache.mirror.anlx.net/zeppelin/zeppelin-0.8.0/zeppelin-0.8.0-bin-all.tgz
ZEPPELIN_MD5="d87a285c0640ed02ad74bea219525364"
ZEPPELIN_VERSION=0.8.0

livy_service_name="LIVYBETA"
livy_service_name_lower="$( echo $livy_service_name | tr '[:upper:]' '[:lower:]' )"
livy_archive="$( basename $LIVY_URL )"
livy_folder="$( basename $livy_archive .zip )"
livy_parcel_folder="${livy_service_name}-${LIVY_VERSION}"
livy_parcel_name="$livy_parcel_folder-el7.parcel"
livy_built_folder="${livy_parcel_folder}_build"
livy_csd_build_folder="livy_csd_build"

zeppelin_service_name="ZEPPELINBETA"
zeppelin_service_name_lower="$( echo $zeppelin_service_name | tr '[:upper:]' '[:lower:]' )"
zeppelin_archive="$( basename $ZEPPELIN_URL )"
zeppelin_folder="$( basename $zeppelin_archive .tgz )"
zeppelin_parcel_folder="${zeppelin_service_name}-${ZEPPELIN_VERSION}"
zeppelin_parcel_name="$zeppelin_parcel_folder-el7.parcel"
zeppelin_built_folder="${zeppelin_parcel_folder}_build"
zeppelin_csd_build_folder="zeppelin_csd_build"

function build_cm_ext {

  #Checkout if dir does not exist
  if [ ! -d cm_ext ]; then
    git clone https://github.com/cloudera/cm_ext.git
  fi
  if [ ! -f cm_ext/validator/target/validator.jar ]; then
    cd cm_ext
    git checkout "$CM_EXT_BRANCH"
    mvn package
    cd ..
  fi
}

function get_livy {
  if [ ! -f "$livy_archive" ]; then
    wget $LIVY_URL
  fi
  livy_md5="$( md5sum $livy_archive | cut -d' ' -f1 )"
  if [ "$livy_md5" != "$LIVY_MD5" ]; then
    echo ERROR: md5 of $livy_archive is not correct
    exit 1
  fi
  if [ ! -d "$livy_folder" ]; then
    unzip $livy_archive
  fi
}

function get_zeppelin {
  if [ ! -f "$zeppelin_archive" ]; then
    wget $ZEPPELIN_URL
  fi
  zeppelin_md5="$( md5sum $zeppelin_archive | cut -d' ' -f1 )"
  if [ "$zeppelin_md5" != "$ZEPPELIN_MD5" ]; then
    echo ERROR: md5 of $zeppelin_archive is not correct
    exit 1
  fi
  if [ ! -d "$zeppelin_folder" ]; then
    tar -xzf $zeppelin_archive
  fi
}

function build_livy_parcel {
  if [ -f "$livy_built_folder/$livy_parcel_name" ] && [ -f "$livy_built_folder/manifest.json" ]; then
    return
  fi
  if [ ! -d $livy_parcel_folder ]; then
    get_livy
    mv $livy_folder $livy_parcel_folder
  fi
  cp -r livy-parcel-src/meta $livy_parcel_folder
  sed -i -e "s/%VERSION%/$LIVY_VERSION/" ./$livy_parcel_folder/meta/parcel.json
  sed -i -e "s/%SERVICENAME%/$livy_service_name/" ./$livy_parcel_folder/meta/parcel.json
  sed -i -e "s/%SERVICENAMELOWER%/$livy_service_name_lower/" ./$livy_parcel_folder/meta/parcel.json
  java -jar cm_ext/validator/target/validator.jar -d ./$livy_parcel_folder
  mkdir -p $livy_built_folder
  tar zcvhf ./$livy_built_folder/$livy_parcel_name $livy_parcel_folder --owner=root --group=root
  java -jar cm_ext/validator/target/validator.jar -f ./$livy_built_folder/$livy_parcel_name
  python cm_ext/make_manifest/make_manifest.py ./$livy_built_folder
}

function build_zeppelin_parcel {
  if [ -f "$zeppelin_built_folder/$zeppelin_parcel_name" ] && [ -f "$zeppelin_built_folder/manifest.json" ]; then
    return
  fi
  if [ ! -d $zeppelin_parcel_folder ]; then
    get_zeppelin
    mv $zeppelin_folder $zeppelin_parcel_folder
  fi
  cp -r zeppelin-parcel-src/meta $zeppelin_parcel_folder
  sed -i -e "s/%VERSION%/$ZEPPELIN_VERSION/" ./$zeppelin_parcel_folder/meta/parcel.json
  sed -i -e "s/%SERVICENAME%/$zeppelin_service_name/" ./$zeppelin_parcel_folder/meta/parcel.json
  sed -i -e "s/%SERVICENAMELOWER%/$zeppelin_service_name_lower/" ./$zeppelin_parcel_folder/meta/parcel.json
  sed -i -e "s/%LIVYSERVICENAME%/$livy_service_name/" ./$zeppelin_parcel_folder/meta/parcel.json
  java -jar cm_ext/validator/target/validator.jar -d ./$zeppelin_parcel_folder
  mkdir -p $zeppelin_built_folder
  tar zcvhf ./$zeppelin_built_folder/$zeppelin_parcel_name $zeppelin_parcel_folder --owner=root --group=root
  java -jar cm_ext/validator/target/validator.jar -f ./$zeppelin_built_folder/$zeppelin_parcel_name
  python cm_ext/make_manifest/make_manifest.py ./$zeppelin_built_folder
}

function build_livy_csd {
  JARNAME=${livy_service_name}-${LIVY_VERSION}.jar
  if [ -f "$JARNAME" ]; then
    return
  fi
  rm -rf ${livy_csd_build_folder}
  cp -rf ./livy-csd-src ${livy_csd_build_folder}
  sed -i -e "s/%SERVICENAME%/$livy_service_name/" ${livy_csd_build_folder}/descriptor/service.sdl
  sed -i -e "s/%SERVICENAMELOWER%/$livy_service_name_lower/" ${livy_csd_build_folder}/descriptor/service.sdl
  sed -i -e "s/%SERVICENAMELOWER%/$livy_service_name_lower/" ${livy_csd_build_folder}/scripts/control.sh
  java -jar cm_ext/validator/target/validator.jar -s ${livy_csd_build_folder}/descriptor/service.sdl -l "SPARK_ON_YARN SPARK2_ON_YARN"

  jar -cvf ./$JARNAME -C ${livy_csd_build_folder} .
}

function build_zeppelin_csd {
  JARNAME=${zeppelin_service_name}-${ZEPPELIN_VERSION}.jar
  if [ -f "$JARNAME" ]; then
    return
  fi
  rm -rf ${zeppelin_csd_build_folder}
  cp -rf ./zeppelin-csd-src ${zeppelin_csd_build_folder}
  sed -i -e "s/%SERVICENAME%/$zeppelin_service_name/" ${zeppelin_csd_build_folder}/descriptor/service.sdl
  sed -i -e "s/%SERVICENAMELOWER%/$zeppelin_service_name_lower/" ${zeppelin_csd_build_folder}/descriptor/service.sdl
  sed -i -e "s/%LIVYSERVICENAME%/$livy_service_name/" ${zeppelin_csd_build_folder}/descriptor/service.sdl
  sed -i -e "s/%LIVYSERVICENAMELOWER%/$livy_service_name_lower/" ${zeppelin_csd_build_folder}/descriptor/service.sdl
  sed -i -e "s/%SERVICENAMELOWER%/$zeppelin_service_name_lower/" ${zeppelin_csd_build_folder}/scripts/control.py
  sed -i -e "s/%LIVYSERVICENAMELOWER%/$livy_service_name_lower/" ${zeppelin_csd_build_folder}/scripts/control.py
  java -jar cm_ext/validator/target/validator.jar -s ${zeppelin_csd_build_folder}/descriptor/service.sdl -l "${livy_service_name}"

  jar -cvf ./$JARNAME -C ${zeppelin_csd_build_folder} .
}

case $1 in
parcel)
  build_cm_ext
  build_livy_parcel
  build_zeppelin_parcel
  ;;
csd)
  build_livy_csd
  build_zeppelin_csd
  ;;
*)
  echo "Usage: $0 [parcel|csd]"
  ;;
esac
