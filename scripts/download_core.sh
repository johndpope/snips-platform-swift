#!/bin/bash

set -e

VERSION="0.61.1"
LIBRARY_NAME=libsnips_megazord
LIBRARY_NAME_A=${LIBRARY_NAME}.a
LIBRARY_NAME_H=${LIBRARY_NAME}.h
OUT_DIR=${PROJECT_DIR}/Dependencies/

if [ -z "$TARGET_BUILD_TYPE" ]; then
TARGET_BUILD_TYPE=$(echo ${CONFIGURATION} | tr '[:upper:]' '[:lower:]')
fi

outdir_for_target_platform () {
    if [ ${PLATFORM_NAME} = macosx ]; then
        return "${OUT_DIR}/macos"
    elif [ ${PLATFORM_NAME} = iphone* ]; then
        return "${OUT_DIR}/ios"
    else
        echo "Platform $PLATFORM_NAME isn't supported" >&2
        exit 1
    fi
}

install_remote_core () {
    echo "Trying remote installation"

    local filename=snips-platform-ios.${VERSION}.tgz # TODO: macos-ios
    local url=https://s3.amazonaws.com/snips/snips-platform-dev/${filename} # TODO: resources.snips.ai or whatever

    echo "Will download '${filename}' in '${OUT_DIR}'"
    if curl --output /dev/null --silent --head --fail "$url"; then
        $(cd ${OUT_DIR} && curl -s ${url} | tar zxv)
    else
        echo "Version ${VERSION} doesn't seem to have been released yet" >&2
        echo "Could not find any file at '${url}'" >&2
        echo "Please file issue on 'https://github.com/snipsco/snips-issues' if you believe this is an issue" >&2
        return 1
    fi
}

install_local_core () {
    echo "Trying local installation"

    # TODO: Find a better way to retrieve root_dir
    local root_dir=${PROJECT_DIR}/../../../
    local target_dir=${root_dir}/target/
    local outdir=$(outdir_for_target_platform)

    if [ "${PLATFORM_NAME}" = iphone* ]; then
        echo "Using iOS local build"
        local archs_array=( ${ARCHS} )

        for arch in "${archs_array[@]}"; do
            if [ ${arch} = arm64 ]; then
                local arch=aarch64
            fi
            local library_path=${target_dir}/${arch}-apple-ios/${TARGET_BUILD_TYPE}/${LIBRARY_NAME_A}
            if [ ! -e ${library_path} ]; then
                echo "Can't find library for arch ${arch}" >&2
                echo "Missing file '${library_path}'" >&2
                return 1
            fi
            cp ${library_path} ${OUT_DIR}/ios/${LIBRARY_NAME}-${arch}.a
        done

        lipo -create `find ${OUT_DIR}/ios/${LIBRARY_NAME}-*.a` -output ${OUT_DIR}/ios/${LIBRARY_NAME_A}
        cp ${root_dir}/snips-megazord/platforms/c/${LIBRARY_NAME}.h ${OUT_DIR}
        cp ${root_dir}/snips-megazord/platforms/c/module.modulemap ${OUT_DIR}

    elif [ "${PLATFORM_NAME}" = macosx ]; then
        echo "Using macOS local build"

        local library_path="${target_dir}/${TARGET_BUILD_TYPE}/${LIBRARY_NAME_A}"
        if [ ! -e ${library_path} ]; then
            echo "Missing file '${library_path}'" >&2
            return 1
        fi
        cp ${library_path} ${OUT_DIR}/macos
        cp ${root_dir}/snips-megazord/platforms/c/${LIBRARY_NAME}.h ${OUT_DIR}/macos
        cp ${root_dir}/snips-megazord/platforms/c/module.modulemap ${OUT_DIR}/macos

    else
        echo "Platform ${PLATFORM_NAME} isn't supported" >&2
        return 1
    fi

    return 0
}

core_is_present () {
    echo "Checking if core is present and complete for platform $PLATFORM_NAME"
    local outdir=$( outdir_for_target_platform )
    echo "OUTDIR_FOR=${outdir}"

    local files_to_check=(
        $outdir/module.modulemap
        $outdir/$LIBRARY_NAME_A
        $outdir/$LIBRARY_NAME_H
    )
    for file in "${files_to_check[@]}"; do
        if [ ! -e $file ]; then
            echo "Core isn't complete" >&2
            echo "Missing file '$file'" >&2
            return 1
        fi
    done

    echo "Core is present"
    return 0
}

core_is_up_to_date () {
    echo "Checking if core is up-to-date"

    local outdir=$( outdir_for_target_platform )
    local header_path=$outdir/${LIBRARY_NAME_H}
    local core_version=$(grep "SNIPS_VERSION" $header_path | cut -d'"' -f2)

    if [ "$core_version" = ${VERSION} ]; then
        echo "Core is up-to-date"
        return 0
    fi

    echo "Found version ${core_version}, expected version ${VERSION}" >&2
    return 1
}

main() {
    if [ -n "${SNIPS_FORCE_REINSTALL}" ]; then
        echo "SNIPS_FORCE_REINSTALL is set"
    else
        if core_is_present && core_is_up_to_date; then
            echo "Core seems present and up-to-date !"
            return 0
        fi
    fi

    mkdir -p ${OUT_DIR}
    echo "Cleaning '${OUT_DIR}' content"
    rm -f ${OUT_DIR}/*

    if [ -n "${SNIPS_USE_LOCAL}" ]; then
        echo "SNIPS_USE_LOCAL is set. Will try local installation only"
        install_local_core && return 0
    elif [ -n "${SNIPS_USE_REMOTE}" ]; then
        echo "SNIPS_USE_REMOTE is set. Will try remote installation only"
        install_remote_core && return 0
    else
        if ! install_local_core; then
            echo "Local installation failed"
            if ! install_remote_core; then
                echo "Remote install failed"
                return 1
            fi
        fi
    fi
}

main "$@" || exit 1
