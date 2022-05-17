#!/bin/sh

function run_test {
    printf "🚀🚀🚀Running Tests NOW\n"
    af-cli package test --coverage

    if [ $? -ne 0 ]; then
        printf "❌❌❌ Oops, not all tests passed ❌❌❌"
    fi
    printf "✅✅✅ Tests Passed\n"
}

function check_coverage {
    printf "\n🚀🚀🚀Checking Code Coverage\n"

    COVERAGE=$(af-cli package coverage summary)
    echo "${COVERAGE}"
    RESULT=$(echo ${COVERAGE} | grep ">>> % Module coverage: 100.00" | wc -l)
    if [ "${RESULT}" -eq "0" ]; then
        echo "❌❌❌ Oops, coverage not 100.00% ❌❌❌"
        exit 1;
    fi
    printf "✅✅✅ Test Coverage Passed\n"
}

run_test
check_coverage
