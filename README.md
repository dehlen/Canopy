# Client

    carthage bootstrap --platform macOS --platform iOS --cache-builds

# Server

    swift build -c release && sudo .build/release/debris

# Sync

    rsync --archive --human-readable --compress --verbose --delete \
          --exclude .build --exclude Carthage --exclude AuthKey_5354D789X6.p8 \
          . canopy:src
