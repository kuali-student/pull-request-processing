#!/usr/bin/env bash
#
# identify-ks-repo-sql-changes.sh
#
# We expect the pull request to have been fetched into target/ks-repo using the
# run-prepare-ks-repo.sh script which does the checkout and sets up the 
# pull-request branch.
#
# This will walk the commit graph to see the changes per pull request commit.
# We want to know the most recent commit (from the pull request branch tip)
# that contains an sql change.
#
# The first sql change containing commit is printed and the script exists with 
# a 1 exit code .

source ./common.sh

KS_REPO=target/ks-repo/.git

PREV_CMT=""

git --git-dir=$KS_REPO log --first-parent HEAD --format=%H | while read CMT
do

	if test -n "$PREV_CMT"
	then
		debug "compute changes between $CMT and $PREV_CMT"
		git --git-dir=$KS_REPO diff --name-status $CMT..$PREV_CMT | grep .sql >/dev/null
		R=$?

		if test 0 -eq $R
		then
			debug "$PREV_CMT contains an sql change"
			echo "$PREV_CMT"
			exit 1;
		else
			# no sql changes
			debug "$PREV_CMT does not contain sql changes"
		fi
	else
		debug "skip"
	fi

	PREV_CMT=$CMT
done

exit 0

