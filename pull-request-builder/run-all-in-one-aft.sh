#!/usr/bin/env bash

# Jenkins script to perform an all in one AFT test
#
# written by Orlando Ramirez (orlando.ramirezmartinez@utoronto.ca)
# enhanced by Haroon Rafique (haroon.rafique@kuali.org)
#
# TODO: Drop database schema after the application is shut down

# maven version 3.2 on jenkins
MVN="mvn"

# make sure all environment variables are set
set -o nounset
# exit immediately if a pipeline returns a non-zero status
set -o errexit

# some default options
AFT_URL="http://mirror.svn.kuali.org/repos/student/test/functional-automation/sambal/trunk"
AFT_STYLE="enr"
REPO_PREFIX="http://mirror.svn.kuali.org/repos/student/enrollment/ks-deployments/tags/builds/ks-deployments-2.1/2.1.1-FR2-M1"
CI_JOB_URL="https://ci.kuali.org/view/student/view/enr-1.0/view/deploy/job/ks-enr-1.0-nightly-build"
ARTIFACT_PREFIX="2.1.1-FR2-M1"
SCHEMA_PREFIX="KSAFT_"

# tomcat variables
TOMCAT_VERSION=7.0.56
export CATALINA_HOME=${WORKSPACE}/tomcat
export CATALINA_OPTS="-Xms512m -Xmx4g -XX:MaxPermSize=512m -verbose:gc -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintHeapAtGC -XX:+PrintTenuringDistribution -Xloggc:${WORKSPACE}/tomcat/logs/heap.log -XX:HeapDumpPath=${WORKSPACE}/tomcat/logs -XX:+HeapDumpOnOutOfMemoryError"
export CATALINA_PID=$(mktemp --suffix .ksaft.catalina 2>/dev/null || mktemp -t .ksaft.catalina)

function usage() {
  cat <<EOT
Usage: $ME

    --debug
        Enable debug messages during execution
    -h|--help
        Print this message and exit.
    --repo_prefix <url of svn code>
        URL of the deployments directory to pull svn code from
        default is http://mirror.svn.kuali.org/repos/student/enrollment/ks-deployments/tags/builds/ks-deployments-2.1/2.1.1-FR2-M1
    --build_job_url <url of build job>
        URL for the CI job that creates the tagged builds
        default is https://ci.kuali.org/view/student/view/enr-1.0/view/deploy/job/ks-enr-1.0-nightly-build
    --aft_url <url for afts>
        URL for AFT code
        default is http://mirror.svn.kuali.org/repos/student/test/functional-automation/sambal/trunk
    --aft_style Type of AFT to run
        Valid values are enr, ksap, cm, smoke
        default is enr
    --artifact_prefix <prefix of artifact version>
        e.g., 2.1.1-FR2-M1 or 2.1.0-FR1, etc.
        default is 2.1.1-FR2-M1
    --schema_prefix <prefix of schema name>
        e.g., KSAFT_JDK8_
        defualt is KSAFT_
    --snapshot
        Run off of SNAPSHOTs (instead of tags)

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

function get_latest_stable_build() {
  dbgprint

  OPT=""
  if [ $DEBUG -eq 0 ]; then OPT="-s"; fi
  BUILD_NUMBER=$(curl $OPT -k $CI_JOB_URL/lastStableBuild/buildNumber)
  echo "${FUNCNAME[0]}: Latest Stable Build Number found: ${BUILD_NUMBER}"
}

function svn_export() {
  dbgprint
  if [ "$1" ]; then
    dbgprint "Exporting repo $1"

    svn info $1
    if [ $SNAPSHOT -ne 0 ]; then
      repo_root=$(svn info $1 | \
        awk '/Repository Root/ {print $3}')

      # obtain information about the individual repos pointed to by the
      # externals

      # externals is an associatve array
      declare -A externals
      # use process substition to read values from command
      while read external local
      do
        externals[$local]=$external
      done < <(svn propget svn:externals $1 | grep '^[^#]')
      #        ^^^ get all external definitions

      for local in "${!externals[@]}"
      do
        echo $local
        # substitute ^ with $repo_root
        svn info ${externals[$local]//^/$repo_root}
      done
    fi

    OPT=""
    if [ $DEBUG -eq 0 ]; then OPT="-q"; fi
    svn $OPT export --force $1 $2
    echo "${FUNCNAME[0]}: svn repo $1 successfully exported"
  fi
}

function initialize_config() {
  dbgprint

  # rice.keystore
  if [ $SNAPSHOT -eq 0 ]
  then
    cp -p \
      ${WORKSPACE}/ks-with-rice-bundled-${BUILD_NUMBER}/src/main/resources/rice.keystore \
      ${HOME}/rice.keystore
  else
    cp -p \
      ${WORKSPACE}/ks-aggregate/ks-deployments/ks-web/ks-with-rice-bundled/src/main/resources/rice.keystore \
      ${HOME}/rice.keystore
  fi

  # config file in ~/kuali/main/dev
  mkdir -p ~/kuali/main/dev
  filepath=src/main/resources/org/kuali/student/ks-deployment-resources/deploy/config
  if [ $SNAPSHOT -eq 0 ]
  then
    cp -p \
      ${WORKSPACE}/ks-deployment-resources-${BUILD_NUMBER}/${filepath}/ks-with-rice-bundled-config.xml \
      ~/kuali/main/dev/ks-with-rice-bundled-config.xml
  else
    cp -p \
      ${WORKSPACE}/ks-aggregate/ks-deployments/ks-deployment-resources/${filepath}/ks-with-rice-bundled-config.xml \
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
    rm -rf ${WORKSPACE}/tomcat
  fi
  set -e
  mkdir -p ${WORKSPACE}/tomcat

  tar xzf /tmp/apache-tomcat-$TOMCAT_VERSION.tar.gz --strip-components=1 \
    -C ${WORKSPACE}/tomcat
  chmod +x ${WORKSPACE}/tomcat/bin/*.sh
  echo "${FUNCNAME[0]}: extracted tomcat to ${WORKSPACE}/tomcat."
}

function install_maven_dependency_plugin() {
  dbgprint

  set -x
  cd ${WORKSPACE}
  ${MVN} org.apache.maven.plugins:maven-dependency-plugin:2.8:get \
        -Dartifact=org.apache.maven.plugins:maven-dependency-plugin:2.8:jar
  if [ $DEBUG -eq 0 ]; then set +x; fi

  echo "${FUNCNAME[0]}: installed maven dependency plugin."
}

function install_oracle_driver() {
  dbgprint

  set -x
  cd ${WORKSPACE}
  ${MVN} org.apache.maven.plugins:maven-dependency-plugin:2.8:copy \
    -Dartifact=com.oracle:ojdbc6_g:11.2.0.2:jar \
    -DoutputDirectory=${WORKSPACE}/tomcat/lib
  if [ $DEBUG -eq 0 ]; then set +x; fi
  echo "${FUNCNAME[0]}: installed oracle driver."
}

function setup_tomcat() {
  dbgprint

  rm -rf ${WORKSPACE}/tomcat/webapps/*
  cat > ${WORKSPACE}/tomcat/conf/server.xml <<EOT
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
        <Context docBase="${WORKSPACE}/tomcat" path="/tomcat"/>
        <Context docBase="\${user.home}" path="/home"/>
      </Host>
    </Engine>
  </Service>
</Server>
EOT
  echo "${FUNCNAME[0]}: tomcat setup finished."
}

function compile_snapshot() {
  dbgprint

  cd ${WORKSPACE}/ks-aggregate
  set -x
  ${MVN} clean install -DskipTests -Pbundled-only-war -Dks.gwt.compile.phase=none
  if [ $DEBUG -eq 0 ]; then set +x; fi
}

function install_war_artifact() {
  dbgprint

  if [ $SNAPSHOT -eq 0 ]
  then
    set -x
    ${MVN} org.apache.maven.plugins:maven-dependency-plugin:2.8:copy \
      -Dartifact=org.kuali.student.web:ks-with-rice-bundled:${ARTIFACT_PREFIX}-build-${BUILD_NUMBER}:war \
      -DoutputDirectory=.
    if [ $DEBUG -eq 0 ]; then set +x; fi

    cp -p ks-with-rice-bundled-${ARTIFACT_PREFIX}-build-${BUILD_NUMBER}.war \
      ${WORKSPACE}/tomcat/webapps/ROOT.war
  else
    cp -p ${WORKSPACE}/ks-aggregate/ks-deployments/ks-web/ks-with-rice-bundled/target/ks-with-rice-bundled-${ARTIFACT_PREFIX}-SNAPSHOT.war \
      ${WORKSPACE}/tomcat/webapps/ROOT.war
  fi
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
  ${WORKSPACE}/jenkinscucumber \
    http://localhost:8080 \
    headless_data \
    headless \
    --threads=4 \
    --parallel=true \
    --firefox=27
}

function run_smoke_afts() {
  ${WORKSPACE}/jenkinscucumber \
    http://localhost:8080 \
    headless_smoke_test_data \
    headless_smoke_test \
    --firefox=27
}

function run_non_enr_afts() {
  set -x
  gem install --no-rdoc --no-ri bundler
  bundle install
  firefox -version
  chmod 777 $WORKSPACE/cleanup_test_processes.sh
  $WORKSPACE/cleanup_test_processes.sh
  cucumber TEST_SITE='http://localhost:8080' \
    FIREFOX_PATH=/usr/bin/firefox27 \
    --profile headless \
    --format pretty \
    --format json \
    --out $WORKSPACE/cucumber1.json --format junit --out .
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

function set_snapshot {
  let "SNAPSHOT+=1"
  REPO_PREFIX="http://mirror.svn.kuali.org/repos/student/enrollment/aggregate/trunk"
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
  check_not_blank AFT_URL $AFT_URL
  check_not_blank AFT_STYLE $AFT_STYLE
  check_not_blank REPO_PREFIX $REPO_PREFIX
  check_not_blank CI_JOB_URL $CI_JOB_URL
  check_not_blank ARTIFACT_PREFIX $ARTIFACT_PREFIX
  check_not_blank SCHEMA_PREFIX $SCHEMA_PREFIX
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
    --longoptions "help,debug,repo_prefix:,build_job_url:,aft_url:,artifact_prefix:,schema_prefix:,aft_style:,snapshot" \
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
      --repo_prefix)
        REPO_PREFIX=$2
        shift 2
        ;;
      --build_job_url)
        CI_JOB_URL=$2
        shift 2
        ;;
      --aft_url)
        AFT_URL=$2
        shift 2
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
      --artifact_prefix)
        ARTIFACT_PREFIX=$2
        shift 2
        ;;
      --schema_prefix)
        SCHEMA_PREFIX=$2
        shift 2
        ;;
      --snapshot)
        set_snapshot
        shift
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

if [ $SNAPSHOT -eq 0 ]; then
  # retrieve latest stable build number
  get_latest_stable_build

  # export impex sources from svn repo to specified path
  svn_export \
    ${REPO_PREFIX}/build-${BUILD_NUMBER}/ks-dbs/ks-impex/ks-impex-bundled-db \
    ${WORKSPACE}/ks-impex-bundled-db-build-${BUILD_NUMBER}

  # export deployment sources from svn repo to specified path
  svn_export \
    ${REPO_PREFIX}/build-${BUILD_NUMBER}/ks-deployment-resources \
    ${WORKSPACE}/ks-deployment-resources-${BUILD_NUMBER}

  # export ks-with-rice-bundled sources from svn repo to specified path
  svn_export \
    ${REPO_PREFIX}/build-${BUILD_NUMBER}/ks-web/ks-with-rice-bundled \
    ${WORKSPACE}/ks-with-rice-bundled-${BUILD_NUMBER}
else
  # export all sources from svn repo to specified path
  svn_export ${REPO_PREFIX} ${WORKSPACE}/ks-aggregate

  # compile snapshot
  compile_snapshot
fi

# export sambal sources from svn repo to specified path
svn_export $AFT_URL ${WORKSPACE}

# initialize config file
initialize_config

# download tomcat
download_tomcat

# extract tomcat
extract_tomcat

# install maven dependency plugin
install_maven_dependency_plugin

# install oracle driver
install_oracle_driver

# setup tomcat
setup_tomcat

# install war artifact
install_war_artifact

# initialize schema (using impex)
initialize_schema

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
