#!/usr/bin/env bats

SCRIPT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)/backup.sh"

setup() {
    MOCK_BIN="$(mktemp -d)"
    export PATH="$MOCK_BIN:$PATH"
    export BOOT_VOLUME_ID="ocid1.bootvolume.oc1.iad.testvol"
    export BACKUP_NAME_PREFIX="test-backup"
    export OCI_CLI_KEY_FILE="/dev/null"
    rm -f "$BATS_TEST_TMPDIR/oci_calls.log"
}

teardown() {
    rm -rf "$MOCK_BIN"
    rm -f "$BATS_TEST_TMPDIR/oci_calls.log"
}

@test "first run: creates backup, does not delete when no existing backup" {
    cat > "$MOCK_BIN/oci" << MOCKEOF
#!/usr/bin/env bash
echo "\$*" >> "$BATS_TEST_TMPDIR/oci_calls.log"
if [[ "\$*" == *"list"* ]]; then
    echo '{"data": []}'
elif [[ "\$*" == *"create"* ]]; then
    echo '{"data": {"id": "ocid1.bootvolumebackup.oc1.iad.new001"}}'
fi
MOCKEOF
    chmod +x "$MOCK_BIN/oci"

    run bash "$SCRIPT"

    [ "$status" -eq 0 ]
    grep -q "create" "$BATS_TEST_TMPDIR/oci_calls.log"
    ! grep -q "delete" "$BATS_TEST_TMPDIR/oci_calls.log"
}

@test "rotation: creates new backup then deletes old one" {
    cat > "$MOCK_BIN/oci" << MOCKEOF
#!/usr/bin/env bash
echo "\$*" >> "$BATS_TEST_TMPDIR/oci_calls.log"
if [[ "\$*" == *"list"* ]]; then
    echo '{"data": [{"display-name": "test-backup-2026-01-01_00-00-00", "id": "ocid1.bootvolumebackup.oc1.iad.old001", "lifecycle-state": "AVAILABLE"}]}'
elif [[ "\$*" == *"create"* ]]; then
    echo '{"data": {"id": "ocid1.bootvolumebackup.oc1.iad.new001"}}'
elif [[ "\$*" == *"delete"* ]]; then
    true
fi
MOCKEOF
    chmod +x "$MOCK_BIN/oci"

    run bash "$SCRIPT"

    [ "$status" -eq 0 ]
    grep -q "create" "$BATS_TEST_TMPDIR/oci_calls.log"
    grep -q "delete" "$BATS_TEST_TMPDIR/oci_calls.log"
    grep -q "ocid1.bootvolumebackup.oc1.iad.old001" "$BATS_TEST_TMPDIR/oci_calls.log"
}

@test "failure: exits non-zero and skips delete when create returns no ID" {
    cat > "$MOCK_BIN/oci" << MOCKEOF
#!/usr/bin/env bash
echo "\$*" >> "$BATS_TEST_TMPDIR/oci_calls.log"
if [[ "\$*" == *"list"* ]]; then
    echo '{"data": [{"display-name": "test-backup-2026-01-01_00-00-00", "id": "ocid1.bootvolumebackup.oc1.iad.old001", "lifecycle-state": "AVAILABLE"}]}'
elif [[ "\$*" == *"create"* ]]; then
    echo '{"data": {"id": ""}}'
fi
MOCKEOF
    chmod +x "$MOCK_BIN/oci"

    run bash "$SCRIPT"

    [ "$status" -ne 0 ]
    ! grep -q "delete" "$BATS_TEST_TMPDIR/oci_calls.log"
}

@test "list failure: treats as first run and creates backup" {
    cat > "$MOCK_BIN/oci" << MOCKEOF
#!/usr/bin/env bash
echo "\$*" >> "$BATS_TEST_TMPDIR/oci_calls.log"
if [[ "\$*" == *"list"* ]]; then
    exit 1
elif [[ "\$*" == *"create"* ]]; then
    echo '{"data": {"id": "ocid1.bootvolumebackup.oc1.iad.new001"}}'
fi
MOCKEOF
    chmod +x "$MOCK_BIN/oci"

    run bash "$SCRIPT"

    [ "$status" -eq 0 ]
    grep -q "create" "$BATS_TEST_TMPDIR/oci_calls.log"
    ! grep -q "delete" "$BATS_TEST_TMPDIR/oci_calls.log"
}

@test "rotation: new backup ID is not the one that gets deleted" {
    cat > "$MOCK_BIN/oci" << MOCKEOF
#!/usr/bin/env bash
echo "\$*" >> "$BATS_TEST_TMPDIR/oci_calls.log"
if [[ "\$*" == *"list"* ]]; then
    echo '{"data": [{"display-name": "test-backup-2026-01-01_00-00-00", "id": "ocid1.bootvolumebackup.oc1.iad.old001", "lifecycle-state": "AVAILABLE"}]}'
elif [[ "\$*" == *"create"* ]]; then
    echo '{"data": {"id": "ocid1.bootvolumebackup.oc1.iad.new001"}}'
elif [[ "\$*" == *"delete"* ]]; then
    true
fi
MOCKEOF
    chmod +x "$MOCK_BIN/oci"

    run bash "$SCRIPT"

    [ "$status" -eq 0 ]
    # old ID must appear in a delete call
    grep "delete" "$BATS_TEST_TMPDIR/oci_calls.log" | grep -q "ocid1.bootvolumebackup.oc1.iad.old001"
    # new ID must NOT appear in any delete call
    ! grep "delete" "$BATS_TEST_TMPDIR/oci_calls.log" | grep -q "ocid1.bootvolumebackup.oc1.iad.new001"
}

@test "failure: exits non-zero when create command itself fails" {
    cat > "$MOCK_BIN/oci" << MOCKEOF
#!/usr/bin/env bash
echo "\$*" >> "$BATS_TEST_TMPDIR/oci_calls.log"
if [[ "\$*" == *"list"* ]]; then
    echo '{"data": []}'
elif [[ "\$*" == *"create"* ]]; then
    exit 1
fi
MOCKEOF
    chmod +x "$MOCK_BIN/oci"

    run bash "$SCRIPT"

    [ "$status" -ne 0 ]
    ! grep -q "delete" "$BATS_TEST_TMPDIR/oci_calls.log"
}

@test "multiple matches: warns and uses first, does not abort" {
    cat > "$MOCK_BIN/oci" << MOCKEOF
#!/usr/bin/env bash
echo "\$*" >> "$BATS_TEST_TMPDIR/oci_calls.log"
if [[ "\$*" == *"list"* ]]; then
    echo '{"data": [{"display-name": "test-backup-2026-01-01_00-00-00", "id": "ocid1.bootvolumebackup.oc1.iad.old001", "lifecycle-state": "AVAILABLE"}, {"display-name": "test-backup-2026-01-02_00-00-00", "id": "ocid1.bootvolumebackup.oc1.iad.old002", "lifecycle-state": "AVAILABLE"}]}'
elif [[ "\$*" == *"create"* ]]; then
    echo '{"data": {"id": "ocid1.bootvolumebackup.oc1.iad.new001"}}'
elif [[ "\$*" == *"delete"* ]]; then
    true
fi
MOCKEOF
    chmod +x "$MOCK_BIN/oci"

    run bash "$SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
    grep -q "create" "$BATS_TEST_TMPDIR/oci_calls.log"
    grep -q "delete" "$BATS_TEST_TMPDIR/oci_calls.log"
}
