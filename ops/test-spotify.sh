#!/usr/bin/env sh
set -eu
token=$(wget -qO- --header "Authorization: Basic $(printf '%s:%s' "$SPOTIFY_CLIENT_ID" "$SPOTIFY_CLIENT_SECRET" | base64 | tr -d '\n')" \
  --post-data 'grant_type=client_credentials' https://accounts.spotify.com/api/token | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
[ -n "$token" ]
printf 'Spotify token acquisition PASS\n'
wget -qO /dev/null --header "Authorization: Bearer $token" \
  'https://api.spotify.com/v1/artists/2iEvnFsWxR0Syqu2JNopAd/albums?include_groups=album&limit=1'
printf 'Spotify artist albums read PASS\n'
