# obsidian-livesync

[`obsidian-livesync`](https://github.com/vrtmrz/obsidian-livesync) is a self-hosted alternative to the paid service [Obsidian Sync](https://obsidian.md/sync).

## Setup

This guide assumes that you have an existing Obsidian vault on one or more devices.

### CouchDB setup

`obsidian-livesync` uses CouchDB for its datastore, so this process will involve setting up this database. Unfortunately, the process is rather manual, which would be nice to change eventually. Many of my instructions are adapted from [this r/selfhosted Reddit post](https://old.reddit.com/r/selfhosted/comments/1eo7knj/guide_obsidian_with_free_selfhosted_instant_sync/); the official documentation is rather confusing at the time of writing.

**Initial container setup**

1) Create a `.env` file to store your desired username and password, plus domain that this will be hosted on:

    ```env
    DOMAIN='example.com'
    COUCHDB_USERNAME='me'
    COUCHDB_PASSWORD='*****'
    ```

2) Spin up the CouchDB container:

    ```bash
    docker compose up -d
    ```

**Initial config**

1) Navigate to the CouchDB admin page `obsidian-livesync.example.com/_utils` on whatever domain you have it hosted on and login with the credentials you specified in `.env`.

2) Expand the menu `<->` and click `Setup`. Select `Configure as Single Node`, enter the same admin credentials, and leave the rest as-is. Finish with `Configure Node`.

3) Verify your installation with the `Verify` section in the left menu, then `Verify Installation`. You should get six checkmarks with a success message.

**Create database(s)**

1) Navigate to `Databases` in the left menu and then `Create Database` in the top right.

2) Enter your database name. I use the format `obsidiandb_{vault_name}` where `vault_name` is the name of your vault in Obsidian. 

3) Ensure that the database is set to `Non-partitioned`, then finish creation.

Repeat this section for as many Obsidian vaults as you'd like to sync.

### Obsidian (client-side) setup

**Set up remote server**

1) Install the community plugin "Self-hosted LiveSync" by voratamoroz.

2) Enable the plugin. When the pop-up appears, choose `Open setting dialog`, then `Options`.

3) In the top bar of the new settings window, choose the satellite icon: 🛰️

4) Fill the fields as follows:

    ```txt
    Remote Type: CouchDB
    URI: https://obsidian-livesync.example.com
    Username: me
    Password: *****
    Database name: obsidiandb_{vault-name}
    ```

5) Select `Test` to ensure the connection works. If it does, a popup will confirm that the plugin "Connected to obsidiandb successfully".

6) Also click `Check` to make sure the database is configured correctly. Checkmarks will appear next to each item that is ready; otherwise, there will be a `Fix` button to help you resolve the issue. Finish with the `Apply` button.

7) Towards the bottom, also turn on `End-to-End Encryption` for database security. Create and save the passphrase securely; you will need it for any subsequent device that connects to the DB. Finish with `Just apply`.

**Set up sync**

1) Return to the top of the settings window, this time choosing the sync icon: 🔄

2) For `Presets`, choose `LiveSync` and then `Apply`.

## TODO

- Automate `obsidiandb` database creation
- Automate script running after container is spun up
