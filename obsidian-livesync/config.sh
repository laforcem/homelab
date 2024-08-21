#!/bin/bash
source .env

if [[ -z "$DOMAIN" ]]; then
    echo "ERROR: Hostname missing, check .env file"
    exit 1
fi
if [[ -z "$COUCHDB_USERNAME" ]]; then
    echo "ERROR: Username missing, check .env file"
    exit 1
fi

if [[ -z "$COUCHDB_PASSWORD" ]]; then
    echo "ERROR: Password missing, check .env file"
    exit 1
fi

hostname="https://obsidian-livesync.$DOMAIN"

echo "Configuring CouchDB via API..."

until (curl -X POST "${hostname}/_cluster_setup" -H "Content-Type: application/json" -d "{\"action\":\"enable_single_node\",\"username\":\"${COUCHDB_USERNAME}\",\"password\":\"${COUCHDB_PASSWORD}\",\"bind_address\":\"0.0.0.0\",\"port\":5984,\"singlenode\":true}" --user "${COUCHDB_USERNAME}:${COUCHDB_PASSWORD}"); do sleep 5; done
until (curl -X PUT "${hostname}/_node/nonode@nohost/_config/chttpd/require_valid_user" -H "Content-Type: application/json" -d '"true"' --user "${COUCHDB_USERNAME}:${COUCHDB_PASSWORD}"); do sleep 5; done
until (curl -X PUT "${hostname}/_node/nonode@nohost/_config/chttpd_auth/require_valid_user" -H "Content-Type: application/json" -d '"true"' --user "${COUCHDB_USERNAME}:${COUCHDB_PASSWORD}"); do sleep 5; done
until (curl -X PUT "${hostname}/_node/nonode@nohost/_config/httpd/WWW-Authenticate" -H "Content-Type: application/json" -d '"Basic realm=\"couchdb\""' --user "${COUCHDB_USERNAME}:${COUCHDB_PASSWORD}"); do sleep 5; done
until (curl -X PUT "${hostname}/_node/nonode@nohost/_config/httpd/enable_cors" -H "Content-Type: application/json" -d '"true"' --user "${COUCHDB_USERNAME}:${COUCHDB_PASSWORD}"); do sleep 5; done
until (curl -X PUT "${hostname}/_node/nonode@nohost/_config/chttpd/enable_cors" -H "Content-Type: application/json" -d '"true"' --user "${COUCHDB_USERNAME}:${COUCHDB_PASSWORD}"); do sleep 5; done
until (curl -X PUT "${hostname}/_node/nonode@nohost/_config/chttpd/max_http_request_size" -H "Content-Type: application/json" -d '"4294967296"' --user "${COUCHDB_USERNAME}:${COUCHDB_PASSWORD}"); do sleep 5; done
until (curl -X PUT "${hostname}/_node/nonode@nohost/_config/couchdb/max_document_size" -H "Content-Type: application/json" -d '"50000000"' --user "${COUCHDB_USERNAME}:${COUCHDB_PASSWORD}"); do sleep 5; done
until (curl -X PUT "${hostname}/_node/nonode@nohost/_config/cors/credentials" -H "Content-Type: application/json" -d '"true"' --user "${COUCHDB_USERNAME}:${COUCHDB_PASSWORD}"); do sleep 5; done
until (curl -X PUT "${hostname}/_node/nonode@nohost/_config/cors/origins" -H "Content-Type: application/json" -d '"app://obsidian.md,capacitor://localhost,http://localhost"' --user "${COUCHDB_USERNAME}:${COUCHDB_PASSWORD}"); do sleep 5; done

echo "Configuring CouchDB by via API complete!"