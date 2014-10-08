#!/bin/bash -e
#
# run-unit-tests.sh
#
# run the unit tests either on the entire project or the named module
#
# Expected Jenkins Build Parameter Names:
# PULL_REQUEST_NUMBER
# PULL_REQUEST_COMMIT_ID
# MODULE <-- optional, if present we only run the unit tests for this module.
#

runModuleTest () {

	M=$1

	# a module is specified so we need to first build the test code for everything
	echo "Running unit tests for module = $M"
	mvn clean install -DskipTests -Dks.gwt.compile.phase=none -Dks.build.angular.phase=none -Pskip-all-wars

	# run unit tests on the identified module only
	echo "cd $M"
	cd $M

	mvn clean install -Dks.gwt.compile.phase=none -Dks.build.angular.phase=none -Dmaven.test.failure.ignore=true -Pskip-all-wars
	
}

runAllTest () {

	PR=$1
	echo "Running all unit tests for pull request $PR"
	# no module is specified so just run the build at the top level
	mvn clean install -Dks.gwt.compile.phase=none -Dks.build.angular.phase=none -Dmaven.test.failure.ignore=true -Pskip-all-wars
}

mvn clean

./run-prepare-ks-repo.sh

if test -z "$MODULE" 
then
	runAllTest $PULL_REQUEST_NUMBER
else 

	if  test "$MODULE" != "all"
	then
		runModuleTest $MODULE
	else
		runAllTest $PULL_REQUEST_NUMBER
	fi
fi	

# EOF
