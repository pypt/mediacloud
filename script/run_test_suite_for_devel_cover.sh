#!/bin/bash
#
# Run the test suite with Devel::Cover, generate coverage report
#
# Usage:
#
#     # create test coverage database, generate HTML report:
#     ./script/run_test_suite_for_devel_cover.sh
#
# or
#
#     # create test coverage database, generate report of type "report_type"
#     # (e.g. "html" or "coveralls"):
#     ./script/run_test_suite_for_devel_cover.sh [report_type]
#

set -e
set -u
set -o errexit

cd `dirname $0`/../

REPORT="html"
if [[ $# == 1 && -n "$1" ]]; then
	REPORT="$1"
fi

echo "Will generate test coverage report: $REPORT"

echo "Removing old test coverage database..." 1>&2
rm -rf cover_db/

echo "Running full test suite..." 1>&2
HARNESS_PERL_SWITCHES='-MDevel::Cover=+ignore,local,+ignore,\.t$' ./script/run_test_suite.sh

echo "Generating '$REPORT' report..." 1>&2
./script/run_carton.sh exec perl local/bin/cover --nogcov -report "$REPORT"

echo "Done." 1>&2
