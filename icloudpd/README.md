# Configuring icloudpd

Once the containers have started, you will need to exec into the container and modify the options directly in the config files.

1. Populate `icloudpd.sample.conf` with desired config changes. Secure information is substituted with variables LIKE_THIS. Copy contents to clipboard.

2. Exec into the container:

    ```sh
    docker exec -it icloudpd-malc sh
    ```

3. Open `/config/icloudpd.conf` and replace its contents with your clipboard.
