#!/bin/bash
set -x
set -e

CM_EXT_BRANCH=cm5-5.12.0
LIVY_URL=http://apache.mirror.anlx.net/incubator/livy/0.4.0-incubating/livy-0.4.0-incubating-bin.zip
LIVY_MD5="0818685b9bc196de2bef9f0dd0e008b3"
LIVY_VERSION=0.4.0

ZEPPELIN_URL=http://apache.mirror.anlx.net/zeppelin/zeppelin-0.7.3/zeppelin-0.7.3-bin-all.tgz
ZEPPELIN_MD5="6f84f5581f59838b632a75071a2157cc"
ZEPPELIN_VERSION=0.7.3


livy_archive="$( basename $LIVY_URL )"
livy_folder="$( basename $livy_archive .zip )"
livy_parcel_folder="LIVY-${LIVY_VERSION}"
livy_parcel_name="$livy_parcel_folder-el7.parcel"
livy_built_folder="${livy_parcel_folder}_build"

zeppelin_archive="$( basename $ZEPPELIN_URL )"
zeppelin_folder="$( basename $zeppelin_archive .tgz )"
zeppelin_parcel_folder="ZEPPELIN-${ZEPPELIN_VERSION}"
zeppelin_parcel_name="$zeppelin_parcel_folder-el7.parcel"
zeppelin_built_folder="${zeppelin_parcel_folder}_build"

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
  java -jar cm_ext/validator/target/validator.jar -d ./$zeppelin_parcel_folder
  mkdir -p $zeppelin_built_folder
  tar zcvhf ./$zeppelin_built_folder/$zeppelin_parcel_name $zeppelin_parcel_folder --owner=root --group=root
  java -jar cm_ext/validator/target/validator.jar -f ./$zeppelin_built_folder/$zeppelin_parcel_name
  python cm_ext/make_manifest/make_manifest.py ./$zeppelin_built_folder
}

function build_livy_csd {
  JARNAME=LIVY-${LIVY_VERSION}.jar
  if [ -f "$JARNAME" ]; then
    return
  fi
  java -jar cm_ext/validator/target/validator.jar -s ./livy-csd-src/descriptor/service.sdl -l "SPARK_ON_YARN SPARK2_ON_YARN"

  jar -cvf ./$JARNAME -C ./livy-csd-src .
}

function build_zeppelin_csd {
  JARNAME=ZEPPELIN-${ZEPPELIN_VERSION}.jar
  if [ -f "$JARNAME" ]; then
    return
  fi
  java -jar cm_ext/validator/target/validator.jar -s ./zeppelin-csd-src/descriptor/service.sdl -l "LIVY"

  jar -cvf ./$JARNAME -C ./zeppelin-csd-src .
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
  if [ -d $livy_parcel_folder ]; then
    rm -rf $livy_parcel_folder
  fi
  if [ -d $livy_built_folder ]; then
    rm -rf $livy_built_folder
  fi
  if [ -f "LIVY-${LIVY_VERSION}.jar" ]; then
    rm -rf "LIVY-${LIVY_VERSION}.jar"
  fi
  ;;
*)
  build_cm_ext
  build_livy_parcel
  build_livy_csd
  build_zeppelin_parcel
  build_zeppelin_csd
  ;;
esac
