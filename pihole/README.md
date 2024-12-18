# Pi-Hole

Pi-hole requires minimal config to get it set up. One secret will need to be added.

## Setup

1. Create a `.env` file.

2. Specify a value `IP_ADDRESS`, which will be the IP of the Pi-Hole. Make sure that the host machine is assigned a static IP in your router to prevent this config from being borked.

3. Run `docker compose up` to get the service running.
