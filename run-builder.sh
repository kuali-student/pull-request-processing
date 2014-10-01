#!/bin/bash -e
#
# run-builder.sh
#
# run the build of a specific pull request on a specific module
#
# Expected Jenkins Build Parameter Names:
# PULL_REQUEST_NUMBER
# PULL_REQUEST_COMMIT_ID
# MODULE
#
REPO_BASE=https://github.com/kuali-student

KS_REPO=$REPO_BASE/ks-development
KS_IMPEX_REPO=$REPO_BASE/ks-development-impex

mvn clean

mkdir -p target

echo "Fetching pull request $PULL_REQUEST_NUMBER head at $PULL_REQUEST_COMMIT_ID"
mvn initialize -DfetchOpenPullRequests.target-pull-request-number=$PULL_REQUEST_NUMBER -DfetchOpenPullRequests.target-commit-id=$PULL_REQUEST_COMMIT_ID -DfetchOpenPullRequests.phase=initialize

cd target/ks-repo

# runs in the subshell to keep the current directory at the top level.
echo "Checkout pull-request-${PULL_REQUEST_NUMBER} branch"
git checkout pull-request-${PULL_REQUEST_NUMBER}

# check that the build works
mvn clean install -DskipTests

# run unit tests on the identified module only
echo "cd $MODULE"
cd $MODULE

mvn clean install -Dks.gwt.compile.phase=none -Dks.build.angular.phase=none

#$(cd target && git clone --depth=1 $KS_IMPEX_REPO ./ks-impex-repo)

# at this point we know if impex is needed
#if test -f target/ks-impex-changes.dat 
#then
#	# need to recreate impex
#	$(cd target/ks-impex-repo && git checkout -b pull-request-${PULL_REQUEST_NUMBER})
#	
#	
#fi

# at this point we know which modules to trigger for unit tests

# EOF