#!/bin/bash

# Exit immediately if any command fails
set -e

build_project() {
    echo "BUILDER STARTING"
    echo "=============="
    echo "[1]: START BUILDING ERLANG MODULES"
    erlc -o ./ebin/ +debug_info src/*.erl
    echo "[DONE BUILDING ERLANG MODULES]"
    echo "=============="
    echo "BUILDER ENDING"
}

clean_project() {
    echo "CLEANING UP..."
    # Suppress errors if no .beam files exist yet
    rm -f *.beam src/*.beam ebin/*.beam
    echo "[DONE CLEANING]"
}

test_project() {
    clean_project
    build_project
    echo "TEST RUNNER STARTING"
    echo "=============="
    for suite in tests/*_tests.escript; do
        echo "[TEST]: $suite"
        escript "$suite"
    done
    echo "[ALL TEST SUITES PASSED]"
    echo "=============="
    echo "TEST RUNNER ENDING"
}

# 2. Read the command line flag ($1)
case "$1" in
    --build|-b)
        # If the user types --build or -b, run the build function
        build_project
        ;;
    
    --clean|-c)
        # If the user types --clean or -c, run the clean function
        clean_project
        ;;
    
    --all|-a)
        # If the user types --all or -a, clean first, then build
        clean_project
        build_project
        ;;

    --test|-t)
        # If the user types --test or -t, build and run all test suites
        test_project
        ;;
    
    *)
        # If the user types nothing, or something we don't recognize, show a help menu
        echo "Error: Invalid or missing flag."
        echo "Usage: ./build.sh [FLAG]"
        echo "Flags:"
        echo "  -b, --build    Compile the Erlang modules"
        echo "  -c, --clean    Remove compiled .beam files"
        echo "  -a, --all      Clean old files and then build"
        echo "  -t, --test     Clean, build, and run every test suite"
        exit 1
        ;;
esac
