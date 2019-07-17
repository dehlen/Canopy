# Requirements

Swift 5.0.2.

# Deploy

The docker image only needs rebuilding if you change the Swift version it
contains.

    docker build --tag pharaoh --build-arg env=staging .
    make

The makefile also deploys any required Swift libraries to the server from the
docker image you built.

# Server Setup

For Ubuntu 16.04 you need a newer curl, so apt remove the system one and build
your own:

    sed -i -e "s/CURL_@CURL_LT_SHLIB_VERSIONED_FLAVOUR@4/CURL_@CURL_LT_SHLIB_VERSIONED_FLAVOUR@3/g" lib/libcurl.vers.in
    ./configure --with-nghttp2 --with-ssl --enable-versioned-symbols --prefix=/usr \
        && make \
        && sudo make install
        && sudo ldconfig

The first line stops Swift outputting annoying warnings every time you run it.

See: https://github.com/matthijs2704/vapor-apns/issues/45#issuecomment-304211439

Git depends on system curl, so build your own:

    ./configure --prefix=/usr --without-tcltk

Finally:

    swift build -c release && sudo .build/release/debris
