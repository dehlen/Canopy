# Client

    carthage bootstrap --platform macOS --platform iOS --cache-builds

# Server

You must install an HTTP2 compliant curl that is new enough from source, then:

    swift build -Xswiftc -I/usr/local/include && sudo LD_LIBRARY_PATH=/usr/local/lib .build/debug/debris

# Sync

    rsync --archive --human-readable --compress --verbose --delete \
          --exclude .build --exclude Carthage --exclude AuthKey_5354D789X6.p8 \
          . canopy:src
