#!/usr/local/bin/bash
if [ ! -e 'lane.pl' ]; then
    echo "This script must run from same directory as lane.pl"
    exit 1;
fi
revisioncount=`git log --oneline | wc -l`
projectversion=`git describe --tags --long`
cleanversion=${projectversion%%-*}

echo "$projectversion-$revisioncount" > SCRIPTVERSION
myd=`pwd`
cd ..
if [ ! -d "xml" ]; then
    echo "Cannot find local XML directory"
    echo "This script should be run from the parser directory"
    exit 1;
fi
cd xml
revisioncount=`git log --oneline | wc -l`
projectversion=`git describe --tags --long`
cleanversion=${projectversion%%-*}

cd $myd
echo "$projectversion-$revisioncount" > XMLVERSION
