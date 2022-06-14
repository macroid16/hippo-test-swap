#!/bin/zsh

# Usage:
#   cat hippo-gen.args | xargs sh hippo-gen.sh

# The path of the hippo swap repo
# The path of the aptos-core repo


CURDIR=$(pwd)

HIPPO_PATH=''
TSGEN_PATH=''
SDK_PATH=''
COPY_TO_HIPPO=0

echo "Current path: ${CURDIR}"

usage() { echo "Usage: $0 [-h /hippo-path] [-t /tsgen-path]  [-s /sdk-path] -r" 1>&2; exit 1; }

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--hippo-path)
          HIPPO_PATH="$2";
          echo "Hippo path: $HIPPO_PATH";
          shift ;;
        -t|--tsgen-path)
          TSGEN_PATH="$2"
          echo "TsGen path: $TSGEN_PATH"
          shift ;;
        -s|--sdk-path)
          SDK_PATH="$2"
          echo "SDK path: $SDK_PATH"
          shift ;;
        -r|--replace-sdk)
          COPY_TO_HIPPO=1
          shift;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done


generate_json() {
  cd "${HIPPO_PATH}" || exit 1
  move package build --json
}

TMPGEN_PATH='/tmp/hippo-tsgen/'

generate_ts() {
  cd "${TSGEN_PATH}" || exit
  rm -rf ${TMPGEN_PATH}
  yarn tsgen ${TMPGEN_PATH} "${HIPPO_PATH}/build/HippoSwap/json"

}

echo "doing: "

generate_json

generate_ts

target_folder="generated"

targetCnt=$((COPY_TO_HIPPO + 0))
if [ "${targetCnt}" -gt 0 ]; then
  echo "Copying:"
  rm -rf "${SDK_PATH}/src/${target_folder}"
  cp -r "${TMPGEN_PATH}" "${SDK_PATH}/src/${target_folder}"
fi

exit 0
