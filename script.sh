#!/usr/bin/env bash

MASON_NAME=gdal
MASON_VERSION=dev
MASON_LIB_FILE=lib/libgdal.a

. ${MASON_DIR:-~/.mason}/mason.sh

function mason_load_source {
    export MASON_BUILD_PATH=${MASON_ROOT}/.build/gdal-2.0
    if [[ ! -d ${MASON_BUILD_PATH} ]]; then
        git clone --depth 1 https://github.com/flippmoke/gdal.git -b build-fixes ${MASON_BUILD_PATH}
    else
        (cd ${MASON_BUILD_PATH} && git pull)
    fi
}

if [[ $(uname -s) == 'Darwin' ]]; then
    FIND_PATTERN="\/Users\/travis\/build\/mapbox\/mason"
else
    FIND_PATTERN="\/home\/travis\/build\/mapbox\/mason"
fi

function install_dep {
    # set up to fix libtool .la files
    # https://github.com/mapbox/mason/issues/61
    REPLACE="$(pwd)"
    REPLACE=${REPLACE////\\/}
    ${MASON_DIR:-~/.mason}/mason install $1 $2
    ${MASON_DIR:-~/.mason}/mason link $1 $2
    LA_FILE=$(${MASON_DIR:-~/.mason}/mason prefix $1 $2)/lib/$3.la
    if [[ -f ${LA_FILE} ]]; then
       perl -i -p -e "s/${FIND_PATTERN}/${REPLACE}/g;" ${LA_FILE}
    else
        echo "$LA_FILE not found"
    fi
}

function mason_prepare_compile {
    cd $(dirname ${MASON_ROOT})
    install_dep libtiff 4.0.4beta libtiff
    install_dep proj 4.8.0 libproj
    install_dep jpeg_turbo 1.4.0 libjpeg
    install_dep libpng 1.6.16 libpng
    install_dep geos 3.4.2-custom libgeos
    # depends on sudo apt-get install zlib1g-dev
    ${MASON_DIR:-~/.mason}/mason install zlib system
    MASON_ZLIB=$(${MASON_DIR:-~/.mason}/mason prefix zlib system)
    # depends on sudo apt-get install libc6-dev
    #${MASON_DIR:-~/.mason}/mason install iconv system
    #MASON_ICONV=$(${MASON_DIR:-~/.mason}/mason prefix iconv system)
}

function mason_compile {
    LINK_DIR="${MASON_ROOT}/.link"
    echo $LINK_DIR
    export LIBRARY_PATH=${LINK_DIR}/lib:${LIBRARY_PATH}

    cd gdal/
    CUSTOM_LIBS="-L${LINK_DIR}/lib -ltiff -ljpeg -lproj -lpng -lgeos"
    CUSTOM_CFLAGS="${CFLAGS} -I${LINK_DIR}/include -I${LINK_DIR}/include/libpng16"
    CUSTOM_CXXFLAGS="${CUSTOM_CFLAGS}"

    # note: we put ${STDLIB_CXXFLAGS} into CXX instead of LDFLAGS due to libtool oddity:
    # http://stackoverflow.com/questions/16248360/autotools-libtool-link-library-with-libstdc-despite-stdlib-libc-option-pass
    if [[ $(uname -s) == 'Darwin' ]]; then
        CXX="${CXX} -stdlib=libc++ -std=c++11"
    fi

    # note: it might be tempting to build with --without-libtool
    # but I find that will only lead to a shared libgdal.so and will
    # not produce a static library even if --enable-static is passed
    LIBS="${CUSTOM_LIBS}" \
    LDFLAGS="${CUSTOM_LDFLAGS}" \
    CFLAGS="${CUSTOM_CFLAGS}" \
    CXXFLAGS="${CUSTOM_CXXFLAGS}" \
    ./configure \
        --enable-static --disable-shared \
        ${MASON_HOST_ARG} \
        --prefix=${MASON_PREFIX} \
        --with-libz=${LINK_DIR} \
        --disable-rpath \
        --with-libjson-c=internal \
        --with-geotiff=internal \
        --with-threads=yes \
        --with-fgdb=no \
        --with-rename-internal-libtiff-symbols=no \
        --with-rename-internal-libgeotiff-symbols=no \
        --with-hide-internal-symbols=yes \
        --with-libtiff=${LINK_DIR} \
        --with-jpeg=${LINK_DIR} \
        --with-png=${LINK_DIR} \
        --with-static-proj4=${LINK_DIR} \
        --with-spatialite=no \
        --with-geos=yes \
        --with-sqlite3=no \
        --with-curl=no \
        --with-xml2=no \
        --with-pcraster=no \
        --with-cfitsio=no \
        --with-odbc=no \
        --with-libkml=no \
        --with-pcidsk=no \
        --with-jasper=no \
        --with-gif=no \
        --with-grib=no \
        --with-freexl=no \
        --with-avx=no \
        --with-sse=no \
        --with-perl=no \
        --with-ruby=no \
        --with-python=no \
        --with-java=no \
        --with-podofo=no \
        --with-pam \
        --with-webp=no \
        --with-pcre=no \
        --with-liblzma=no \
        --with-netcdf=no \
        --with-poppler=no

    make -j${MASON_CONCURRENCY}
    make install

    # attempt to make paths relative in gdal-config
    python -c "data=open('$MASON_PREFIX/bin/gdal-config','r').read();open('$MASON_PREFIX/bin/gdal-config','w').write(data.replace('$MASON_PREFIX','\$( cd \"\$( dirname \$( dirname \"\$0\" ))\" && pwd )'))"
    # fix paths to all deps to point to mason_packages/.link
    python -c "data=open('$MASON_PREFIX/bin/gdal-config','r').read();open('$MASON_PREFIX/bin/gdal-config','w').write(data.replace('$MASON_ROOT','./mason_packages'))"
    
    cat $MASON_PREFIX/bin/gdal-config
}

function mason_cflags {
    echo "-I${MASON_PREFIX}/include/gdal"
}

function mason_ldflags {
    echo $(${MASON_PREFIX}/bin/gdal-config --static --libs)
}

function mason_clean {
    make clean
}

mason_run "$@"
