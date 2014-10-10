#!/usr/bin/env bash

# Jenkins script to perform an all in one AFT test
#
# written by Orlando Ramirez (orlando.ramirezmartinez@utoronto.ca)
# enhanced by Haroon Rafique (haroon.rafique@kuali.org)
# modified for Git by Michael O'Cleirigh (michael.ocleirigh@kuali.org)
#
# The Git version expects target/ks-repo to exist and target/ks-impex-repo to exist
#
# Both repositories should be setup on the pull-request-X version and the artifacts should already be compiled.
# We then start with running the manual impex process for bundled.

# maven version 3.2 on jenkins
MVN="mvn"

# make sure all environment variables are set
set -o nounset
# exit immediately if a pipeline returns a non-zero status
set -o errexit

if test -z "$MAVEN_USERNAME"
then
	echo "Missing MAVEN_USERNAME Variable"
	exit 1
fi

if test -z "$MAVEN_PASSWORD"
then
	echo "Missing MAVEN_PASSWORD Variable"
	exit 1
fi

# some default options
KS_REPO=${WORKSPACE}/pull-request-builder/target/ks-repo
KS_IMPEX_REPO=${WORKSPACE}/pull-request-builder/target/ks-impex-repo
KS_AFT_REPO=${WORKSPACE}/pull-request-builder/target/ks-aft-repo

# tomcat variables
TOMCAT_VERSION=7.0.56
export CATALINA_HOME=${WORKSPACE}/pull-request-builder/target/tomcat
export CATALINA_OPTS="-Xms512m -Xmx4g -XX:MaxPermSize=512m -verbose:gc -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintHeapAtGC -XX:+PrintTenuringDistribution -Xloggc:${CATALINA_HOME}/logs/heap.log -XX:HeapDumpPath=${CATALINA_HOME}/logs -XX:+HeapDumpOnOutOfMemoryError"
export CATALINA_PID=$(mktemp --suffix .ksaft.catalina 2>/dev/null || mktemp -t .ksaft.catalina)

function usage() {
  cat <<EOT
Usage: $ME

    --debug
        Enable debug messages during execution
    -h|--help
        Print this message and exit.
    --aft_style Type of AFT to run
        Valid values are enr, ksap, cm, smoke
        default is enr

EOT
    exit 2
}


function dbgprint() {
  if [ $DEBUG -ne 0 ]; then
    set +x
    msg="$(date +%Y-%m-%d-%H:%M):"
    msg="$msg ${FUNCNAME[1]}: "
    for arg in $*
    do
      msg="$msg $arg"
    done
    echo -e "$msg"
    set -x
  fi
}

function initialize_config() {
  dbgprint

  # rice.keystore
  if [ $SNAPSHOT -eq 0 ]
  then
    cp -p \
      ${KS_REPO}/ks-deployments/ks-web/ks-with-rice-bundled/src/main/resources/rice.keystore \
      ${HOME}/rice.keystore
  fi

  # config file in ~/kuali/main/dev
  mkdir -p ~/kuali/main/dev
  filepath=src/main/resources/org/kuali/student/ks-deployment-resources/deploy/config
  if [ $SNAPSHOT -eq 0 ]
  then
    cp -p \
      ${KS_REPO}/ks-deployments/ks-deployment-resources/${filepath}/ks-with-rice-bundled-config.xml \
      ~/kuali/main/dev/ks-with-rice-bundled-config.xml
  fi

  echo "${FUNCNAME[0]}: config initialized successfully"
}

function initialize_schema() {
  dbgprint

  # replace non alpha-numeric characters with underscore (_) in schema name
  if [ $SNAPSHOT -eq 0 ]
  then
    SANITIZED_SCHEMA="${SCHEMA_PREFIX}NIGHTLY"
  else
    SANITIZED_SCHEMA="${SCHEMA_PREFIX}SNAPSHOT"
  fi

  # do some substitutions (note: schema name has been uppercased using ^^)
  sed -i.bak \
    -e "s#\${public.url}#http://localhost:8080#g" \
    -e "s#\${jdbc.url}#jdbc:oracle:thin:@oracle.ks.kuali.org:1521:ORACLE#g" \
    -e "s#\${jdbc.username}#${SANITIZED_SCHEMA^^}#g" \
    -e "s#\${jdbc.password}#${SANITIZED_SCHEMA^^}#g" \
    -e "s#\${jdbc.pool.size.max}#20#g" \
    -e "s#\${rice.krad.dev.mode}#false#g" \
    -e "s#\${keystore.file.default}#${HOME}/rice.keystore#g" \
        ~/kuali/main/dev/ks-with-rice-bundled-config.xml

  dbgprint $(cat ~/kuali/main/dev/ks-with-rice-bundled-config.xml)

  if [ $SNAPSHOT -eq 0 ]
  then
    cd ${WORKSPACE}/ks-impex-bundled-db-build-${BUILD_NUMBER}
  else
    set -x
    cd ${WORKSPACE}/ks-aggregate
    ${MVN} clean install -Pimpex-only
    cd ${WORKSPACE}/ks-aggregate/ks-deployments/ks-dbs/ks-impex/ks-impex-bundled-db
  fi

  # load bundled schema (note: schema name has been uppercased)
  set -x
  ${MVN} initialize -Pdb,oracle,sonar \
    -Djdbc.username=${SANITIZED_SCHEMA^^} -Djdbc.username=${SANITIZED_SCHEMA^^}
  if [ $DEBUG -eq 0 ]; then set +x; fi
}

function download_tomcat() {
  dbgprint
  OPT=""
  if [ $DEBUG -eq 0 ]; then OPT="--no-verbose"; fi

  wget $OPT -O /tmp/apache-tomcat-$TOMCAT_VERSION.tar.gz \
    http://archive.apache.org/dist/tomcat/tomcat-7/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz

  # stop building if md5sum does not match
  echo "2887d0e3ca18bdca63004a0388c99775  /tmp/apache-tomcat-$TOMCAT_VERSION.tar.gz" | \
    md5sum -c -
  echo "${FUNCNAME[0]}: downloaded tomcat $TOMCAT_VERSION."
}

function extract_tomcat() {
  dbgprint

  # detect if tomcat is already running
  # temporarily override immediate exit
  set +e
  pgrep -fl catalina
  # found any processes
  if [ $? -eq 0 ]; then
    echo "found existing tomcat process. Killing it."
    # kill running catalina process
    pkill -9 -f catalina
    rm -rf ${CATALINA_HOME}
  fi
  set -e
  mkdir -p ${CATALINA_HOME}

  tar xzf /tmp/apache-tomcat-$TOMCAT_VERSION.tar.gz --strip-components=1 \
    -C ${CATALINA_HOME}
  chmod +x ${CATALINA_HOME}/bin/*.sh
  echo "${FUNCNAME[0]}: extracted tomcat to ${CATALINA_HOME}."
}

function install_oracle_driver() {
  dbgprint

  set -x
  
  wget --http-username=$MAVEN_USERNAME --http-password=$MAVEN_PASSWORD http://nexus.kuali.org/service/local/repo_groups/developer/content/com/oracle/ojdbc6/11.2.0.2/ojdbc6-11.2.0.2.jar -o ${CATALINA_HOME}/lib
  
  if [ $DEBUG -eq 0 ]; then set +x; fi
  echo "${FUNCNAME[0]}: installed oracle driver."
}

function setup_tomcat() {
  dbgprint

  rm -rf ${CATALINA_HOME}/webapps/*
  cat > ${CATALINA_HOME}/conf/server.xml <<EOT
<?xml version='1.0' encoding='utf-8'?>
<Server port="8005" shutdown="SHUTDOWN">
  <!-- SecurityListener commented out to allow root to run tomcat -->
  <!--Listener className="org.apache.catalina.security.SecurityListener" /-->
  <Listener className="org.apache.catalina.core.AprLifecycleListener" SSLEngine="on" />
  <Listener className="org.apache.catalina.core.JasperListener" />
  <Listener className="org.apache.catalina.core.JreMemoryLeakPreventionListener" />
  <Listener className="org.apache.catalina.mbeans.GlobalResourcesLifecycleListener" />
  <Listener className="org.apache.catalina.core.ThreadLocalLeakPreventionListener" />
  <Service name="Catalina">
    <Connector port="8080" protocol="HTTP/1.1" 
               connectionTimeout="20000" 
               redirectPort="8443" />
    <Connector port="8009" protocol="AJP/1.3" redirectPort="8443" />
    <Engine name="Catalina" defaultHost="localhost">
      <Host name="localhost"  appBase="webapps"
            unpackWARs="true" autoDeploy="true"
            xmlValidation="false" xmlNamespaceAware="false">
        <Context docBase="${CATALINA_HOME}" path="/tomcat"/>
        <Context docBase="\${user.home}" path="/home"/>
      </Host>
    </Engine>
  </Service>
</Server>
EOT
  echo "${FUNCNAME[0]}: tomcat setup finished."
}

function compile_pull_request() {
  dbgprint

   set -x
  ${MVN} clean install -DskipTests -Pbundled-only-war -Dks.gwt.compile.phase=none
  if [ $DEBUG -eq 0 ]; then set +x; fi
}

function install_war_artifact() {
  dbgprint

  # copy assembled war file into tomcat webapps directory
    cp -p ${KS_REPO}/ks-deployments/ks-web/ks-with-rice-bundled/target/ks-with-rice-bundled-*.war \
      ${CATALINA_HOME}/webapps/ROOT.war
  
  echo "${FUNCNAME[0]}: installation of war finished."
}

function start_tomcat() {
  dbgprint

  rm -f $CATALINA_PID
  # start up tomcat
  dbgprint ${CATALINA_HOME}/bin/startup.sh
  echo "Staring Tomcat..."
  ${CATALINA_HOME}/bin/startup.sh 2>&1

  # timeout will be exceeded in LIMIT*SLEEP seconds
  LIMIT=30
  SLEEP=10

  # temporarily override immediate exit
  set +e
  a=0
  while [ $a -le "$LIMIT" ]
  do
    remaining=$((($LIMIT-$a)*$SLEEP))
    a=$(($a+1))
    website=$(curl -s -k --max-time $SLEEP --connect-timeout $SLEEP http://localhost:8080/login.jsp)
    found=$(echo $website| grep 'Kuali Student Login')
    if [ $? -eq 0 ]
    then
      break
    else
      echo "Tomcat is not up (timeout in $remaining seconds)"
    fi
    sleep $SLEEP
  done
  set -e
   
  if [ $a -ge "$LIMIT" ]
  then
    echo "Timeout of $(($LIMIT*$SLEEP)) seconds exceeded"
    cleanup_tomcat
    exit 1
  fi

  echo "${FUNCNAME[0]}: tomcat startup finished."
}

function run_enr_afts() {
  ${KS_AFT_REPO}/jenkinscucumber \
    http://localhost:8080 \
    headless_data \
    headless \
    --threads=4 \
    --parallel=true \
    --firefox=27
}

function run_smoke_afts() {
  ${KS_AFT_REPO}/jenkinscucumber \
    http://localhost:8080 \
    headless_smoke_test_data \
    headless_smoke_test \
    --firefox=27
}

function run_non_enr_afts() {
  set -x
  cd $KS_AFT_REPO
  gem install --no-rdoc --no-ri bundler
  bundle install
  firefox -version
  chmod 777 ${KS_AFT_REPO}/cleanup_test_processes.sh
  $KS_AFT_REPO/cleanup_test_processes.sh
  cucumber TEST_SITE='http://localhost:8080' \
    FIREFOX_PATH=/usr/bin/firefox27 \
    --profile headless \
    --format pretty \
    --format json \
    --out $KS_AFT_REPO/cucumber1.json --format junit --out .
  if [ $DEBUG -eq 0 ]; then set +x; fi
}

function run_afts() {
  dbgprint

  echo "${FUNCNAME[0]}: Running AFTs"
  cd ${WORKSPACE}

  # temporarily override immediate exit
  set +e
  case $AFT_STYLE in
    enr)  run_enr_afts;;
    cm)   run_non_enr_afts;;
    ksap) run_non_enr_afts;;
    smoke)  run_smoke_afts;;
    *)
      echo "Invalid AFT_STYLE '${AFT_STYLE}'"
      usage
      ;;
  esac
  set -e
  echo "${FUNCNAME[0]}: AFTs finished."
}

function cleanup_tomcat() {
  dbgprint

  # wait 30 seconds while sutting down tomcat, then use force!!
  ${CATALINA_HOME}/bin/shutdown.sh 30 -force 2>&1
  echo "waiting for Tomcat to exit (PID: $(cat $CATALINA_PID))... "
  wait $(cat $CATALINA_PID)
  echo "${FUNCNAME[0]}: tomcat shutdown finished."
}

function set_debug_mode {
  let "DEBUG+=1"
  set -x
}

# check that a variable is set and is not the empty string
function check_not_blank {
  if [ ! -n "$2" ]; then
    echo $1 cannot be blank
    usage
  fi
}

# make sure we have all the arguments we need to proceed
function check_args {
  check_not_blank AFT_STYLE $AFT_STYLE
}

function process_args {
  DEBUG=0
  BUILD_NUMBER=0
  SNAPSHOT=0

  # temporarily override immediate exit
  set +e

  # --options specifies short options
  # --longoptions specifies long options
  args=$(getopt \
    --options h \
    --longoptions "help,debug,aft_style: \
    --name "$ME" -- "$@")

  if [ $? != 0 ]
  then
    usage
  fi

  eval set -- "$args"

  while true
  do
    case "$1" in
      -h|--help)
        usage
        ;;
      --debug)
        set_debug_mode
        shift
        ;;
      --aft_style)
        AFT_STYLE=$2
        case $AFT_STYLE in
          enr|ksap|cm|smoke)
            # valid options
            ;;
          *)
            echo "\n    Invalid AFT style '${AFT_STYLE}' chosen\n"
            usage
            ;;
        esac
        shift 2
        ;;
      --)
        shift
        break
        ;;
    esac
  done
  set -e
}

ME=$(basename $0)

# process all of our command line arguments
process_args "$@"

# make sure we have what we need to proceed
check_args

# compile things first
cd $KS_REPO

# compile the pull request
compile_pull_request

cd ../..

cd $KS_IMPEX_REPO
# build the .mpx containing jars
mvn clean install

cd ../..

cd $KS_REPO

cd ks-deployments/ks-dbs/ks-impex

mvn initialize -Pdb,oracle,ks-impex-bundled-db -Dproperties.decrypt=false -o

# initialize config file
initialize_config

# download tomcat
download_tomcat

# extract tomcat
extract_tomcat

# install oracle driver
install_oracle_driver

# setup tomcat
setup_tomcat

# install war artifact
install_war_artifact

# initialize schema (using impex)
#initialize_schema

# register the cleanup function as callback to execute when a signal
# is sent to this process
trap cleanup_tomcat EXIT SIGINT SIGTERM

# start tomcat
start_tomcat

# run AFTs
run_afts

# process was successful, so reset trap and cleanup normally
trap - EXIT SIGINT SIGTERM
cleanup_tomcat

# vim: tabstop=2 shiftwidth=2 syntax=sh filetype=sh
