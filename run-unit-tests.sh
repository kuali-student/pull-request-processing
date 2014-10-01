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

mvn clean

mkdir -p target

echo "Fetching pull request $PULL_REQUEST_NUMBER head at $PULL_REQUEST_COMMIT_ID from github"
mvn initialize -DfetchOpenPullRequests.target-pull-request-number=$PULL_REQUEST_NUMBER -DfetchOpenPullRequests.target-commit-id=$PULL_REQUEST_COMMIT_ID -DfetchOpenPullRequests.phase=initialize

cd target/ks-repo

# runs in the subshell to keep the current directory at the top level.
echo "Checkout pull-request-${PULL_REQUEST_NUMBER} branch"
git checkout pull-request-${PULL_REQUEST_NUMBER}

if test "$MODULE" != "all
then
	# a module is specified so we need to first build the test code for everything
	echo "Running unit tests for module = $MODULE"
	mvn clean install -DskipTests

	# run unit tests on the identified module only
	echo "cd $MODULE"
	cd $MODULE

	mvn clean install -Dks.gwt.compile.phase=none -Dks.build.angular.phase=none

else
	echo "Running all unit tests for pull request $PULL_REQUEST_NUMBER"
	# no module is specified so just run the build at the top level
	mvn clean install -Dks.gwt.compile.phase=none -Dks.build.angular.phase=none
fi

# EOF