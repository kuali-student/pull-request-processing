#!/usr/bin/env bash
#
# create target/ks-aft-repo
# change the current directory to target/ks-aft-repo
# change the current branch to pull-request-X
#
# to start with just setup with trunk.
# In the future we might want to have the a pairing between the aft and the 
# Allows for the PULL_REQUEST_NUMBER environment variables to exist.  If defined this is the name of the 
# 

if test -z $PULL_REQUEST_NUMBER
then
	echo "Missing PULL_REQUEST_NUMBER Variable"
	exit 1
fi

mkdir -p target

git clone --depth=1 https://github.com/kuali-student/functional-automation.git target/ks-aft-repo

cd target/ks-aft-repo

# runs in the subshell to keep the current directory at the top level.
echo "Checkout pull-request-${PULL_REQUEST_NUMBER} branch"
git checkout -b ks-pull-request-${PULL_REQUEST_NUMBER}

cd ../..

# EOF
