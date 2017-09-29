#!/bin/bash
set -x
set -e

CM_EXT_BRANCH=cm5-5.12.0
LIVY_URL=http://apache.mirror.anlx.net/incubator/livy/0.4.0-incubating/livy-0.4.0-incubating-bin.zip
LIVY_MD5="0818685b9bc196de2bef9f0dd0e008b3"
LIVY_VERSION=0.4.0


livy_archive="$( basename $LIVY_URL )"
livy_folder="$( basename $livy_archive .zip )"
parcel_folder="LIVY-${LIVY_VERSION}"
parcel_name="$parcel_folder-el7.parcel"

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

function build_parcel {
  if [ -f $parcel_name ]; then
    return
  fi
  if [ ! -d $parcel_folder ]; then
    get_livy
    mv $livy_folder $parcel_folder
  fi
  cp -r parcel-src/meta $parcel_folder
  sed -i -e "s/%VERSION%/$LIVY_VERSION/" ./$parcel_folder/meta/parcel.json
  java -jar cm_ext/validator/target/validator.jar -d ./$parcel_folder
  tar zcvhf ./$parcel_name $parcel_folder --owner=root --group=root
  java -jar cm_ext/validator/target/validator.jar -f ./$parcel_name
}

case $1 in
clean)
  if [ -d cm_ext ]; then
    rm -rf cm_ext
  fi
  if [ -d $livy_folder ]; then
    rm -rf $livy_folder
  fi
  if [ -f $livy_archive ]; then
    rm -rf $livy_archive
  fi
  if [ -d $parcel_folder ]; then
    rm -rf $parcel_folder
  fi
  if [ -f $parcel_name ]; then
    rm -rf $parcel_name
  fi
  ;;
*)
  build_cm_ext
  build_parcel
  ;;
esac
