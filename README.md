# Client

    carthage bootstrap --platform macOS --platform iOS --cache-builds

# Server

    swift build -c release && sudo .build/release/debris

# Sync

    rsync --archive --human-readable --compress --verbose --delete \
          --exclude .build --exclude Carthage --exclude AuthKey_5354D789X6.p8 \
          . canopy:src

# Notable Missing Events

There are no webhooks (or often other types of event) for these:

* Repositories renamed
* Gist creation
* Activity on other repos you watch that have no hooks
  eg. you comment on a thread, now you are subscribed, you'll get an email and
  notification bell about this on github.com, but Canopy cannot see this unless
  they have a webhook installed and you subscribe to that repo, but then you
  get *all* notifications, which isn’t what you want. I guess if they have it installed
  we could notify you sine you are involved. We could figure that out.