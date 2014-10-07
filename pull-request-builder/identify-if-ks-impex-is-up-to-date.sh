#!/usr/bin/env bash
#
# identify-if-ks-impex-is-up-to-date.sh
#
# We expect the target/ks-impex-repo to have been setup already.
#
# We expect the LATEST_KS_REPO_SQL_CHANGE_ID variable to exist and to hold the
# commit id of the target/ks-repo commit that has the most recent sql change.
#
# This script returns 0 if the latest commit to the target/ks-impex-repo

source ./common.sh

KS_IMPEX_REPO=target/ks-impex-repo/.git

if test -z "$LATEST_KS_REPO_SQL_CHANGE_ID"
then
	echo "Missing expected variable LATEST_KS_REPO_SQL_CHANGE_ID"
	exit 1
fi

git --git-dir=$KS_IMPEX_REPO log -n 1 | grep $LATEST_KS_REPO_SQL_CHANGE_ID > /dev/null

R=$?

if test 0 -eq $R
then
	debug "UP TO DATE: The target commit id is contained in the latest commit message."
	exit 0;
else
	debug "IMPEX REQUIRED: the target commit message is not in the message which means we need to reimpex."
	exit 1;
fi

