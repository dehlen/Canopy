# Client

    carthage bootstrap --platform macOS --platform iOS --cache-builds

# Server

Strongly recommend Swift 4.2+ due to several important HTTP engine fixes.

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

# Sync

    rsync --archive --human-readable --compress --verbose --delete \
          --exclude .build --exclude Carthage \
          . canopy:src
