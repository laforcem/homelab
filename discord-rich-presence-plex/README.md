# Setup

Since YAML is incapable of interpolating envionment variables, copy the below contents into `./data/config.yaml`, substituting your Plex token where needed.

```yaml
logging:
  debug: true
  writeToFile: false
display:
  duration: false
  genres: true
  album: true
  albumImage: true
  artist: true
  artistImage: false
  year: false
  statusIcon: false
  progressMode: bar
  statusTextType:
    watching: title
    listening: artist
  paused: false
  posters:
    enabled: true
    imgurClientID: ''
    maxSize: 256
    fit: true
  buttons: []
users:
  - token: YOUR_TOKEN_HERE
    servers:
      - name: Starcliff Lab
```
