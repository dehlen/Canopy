# Client

    carthage bootstrap --platform macOS --platform iOS --cache-builds

# Server

    swift build -c release && sudo .build/release/debris

# Sync

    rsync --archive --human-readable --compress --verbose --delete \
          --exclude .build --exclude Carthage --exclude AuthKey_5354D789X6.p8 \
          . canopy:src
  
# FAQ

> I cannot see a particular private repo.

The GitHub API does not return results for private repositories forked from private repositories that are not organizations.
To add such repositories you have to create a personal-access-token and replace the keychain entry for Canopy with that token.

> I do not get certain notifications I was expecting

Canopy can only report activity that is supported by GitHub’s webhook system, notably this does not include:

* Activity on other people’s repositories that you are watching
* Activity on issue trackers that occurs after you have commented
* Activity on your gists
* Repository rename events

> Why do you ask for full access to my repositories

Unfortunately this permission is the lowest we can request in order to list your private repositories.

GitHub need to offer more granularity in their permission scope system.