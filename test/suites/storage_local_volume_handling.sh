test_storage_local_volume_handling() {
  ensure_import_testimage

  # shellcheck disable=2039,3043
  local INCUS_STORAGE_DIR incus_backend
  incus_backend=$(storage_backend "$INCUS_DIR")
  INCUS_STORAGE_DIR=$(mktemp -d -p "${TEST_DIR}" XXXXXXXXX)
  chmod +x "${INCUS_STORAGE_DIR}"
  spawn_incus "${INCUS_STORAGE_DIR}" false

  ensure_import_testimage

  (
    set -e
    # shellcheck disable=2030
    INCUS_DIR="${INCUS_STORAGE_DIR}"

    if storage_backend_available "btrfs"; then
      incus storage create "incustest-$(basename "${INCUS_DIR}")-btrfs" btrfs size=1GiB
    fi

    if storage_backend_available "ceph"; then
      incus storage create "incustest-$(basename "${INCUS_DIR}")-ceph" ceph volume.size=25MiB ceph.osd.pg_num=16
      if [ -n "${INCUS_CEPH_CEPHFS:-}" ]; then
        incus storage create "incustest-$(basename "${INCUS_DIR}")-cephfs" cephfs source="${INCUS_CEPH_CEPHFS}/$(basename "${INCUS_DIR}")-cephfs"
      fi
    fi

    incus storage create "incustest-$(basename "${INCUS_DIR}")-dir" dir

    if storage_backend_available "lvm"; then
      incus storage create "incustest-$(basename "${INCUS_DIR}")-lvm" lvm volume.size=25MiB
    fi

    if storage_backend_available "zfs"; then
      incus storage create "incustest-$(basename "${INCUS_DIR}")-zfs" zfs size=1GiB
    fi

    # Test all combinations of our storage drivers

    driver="${incus_backend}"
    pool_opts=

    if [ "$driver" = "btrfs" ] || [ "$driver" = "zfs" ]; then
      pool_opts="size=1GiB"
    fi

    if [ "$driver" = "ceph" ]; then
      pool_opts="volume.size=25MiB ceph.osd.pg_num=16"
    fi

    if [ "$driver" = "lvm" ]; then
      pool_opts="volume.size=25MiB"
    fi

    if [ -n "${pool_opts}" ]; then
      # shellcheck disable=SC2086
      incus storage create "incustest-$(basename "${INCUS_DIR}")-${driver}1" "${driver}" $pool_opts
    else
      incus storage create "incustest-$(basename "${INCUS_DIR}")-${driver}1" "${driver}"
    fi

    incus storage volume create "incustest-$(basename "${INCUS_DIR}")-${driver}" vol1
    incus storage volume set "incustest-$(basename "${INCUS_DIR}")-${driver}" vol1 user.foo=snap0
    incus storage volume set "incustest-$(basename "${INCUS_DIR}")-${driver}" vol1 snapshots.expiry=1H

    # This will create the snapshot vol1/snap0
    incus storage volume snapshot create "incustest-$(basename "${INCUS_DIR}")-${driver}" vol1

    # This will create the snapshot vol1/snap1
    incus storage volume set "incustest-$(basename "${INCUS_DIR}")-${driver}" vol1 user.foo=snap1
    incus storage volume snapshot create "incustest-$(basename "${INCUS_DIR}")-${driver}" vol1
    incus storage volume set "incustest-$(basename "${INCUS_DIR}")-${driver}" vol1 user.foo=postsnap1

    # Copy volume with snapshots in same pool
    incus storage volume copy "incustest-$(basename "${INCUS_DIR}")-${driver}/vol1" "incustest-$(basename "${INCUS_DIR}")-${driver}/vol1copy"

    # Ensure the target snapshots are there
    incus storage volume snapshot show "incustest-$(basename "${INCUS_DIR}")-${driver}" vol1copy/snap0
    incus storage volume snapshot show "incustest-$(basename "${INCUS_DIR}")-${driver}" vol1copy/snap1

    # Check snapshot volume config was copied
    incus storage volume get "incustest-$(basename "${INCUS_DIR}")-${driver}" vol1copy user.foo | grep -Fx "postsnap1"
    incus storage volume get "incustest-$(basename "${INCUS_DIR}")-${driver}" vol1copy/snap0 user.foo | grep -Fx "snap0"
    incus storage volume get "incustest-$(basename "${INCUS_DIR}")-${driver}" vol1copy/snap1 user.foo | grep -Fx "snap1"
    incus storage volume delete "incustest-$(basename "${INCUS_DIR}")-${driver}" vol1copy

    # Copy volume with snapshots in different pool
    incus storage volume copy "incustest-$(basename "${INCUS_DIR}")-${driver}/vol1" "incustest-$(basename "${INCUS_DIR}")-${driver}1/vol1"

    # Ensure the target snapshots are there
    incus storage volume snapshot show "incustest-$(basename "${INCUS_DIR}")-${driver}1" vol1/snap0
    incus storage volume snapshot show "incustest-$(basename "${INCUS_DIR}")-${driver}1" vol1/snap1

    # Check snapshot volume config was copied
    incus storage volume get "incustest-$(basename "${INCUS_DIR}")-${driver}1" vol1 user.foo | grep -Fx "postsnap1"
    incus storage volume get "incustest-$(basename "${INCUS_DIR}")-${driver}1" vol1/snap0 user.foo | grep -Fx "snap0"
    incus storage volume get "incustest-$(basename "${INCUS_DIR}")-${driver}1" vol1/snap1 user.foo | grep -Fx "snap1"

    # Copy volume only
    incus storage volume copy --volume-only "incustest-$(basename "${INCUS_DIR}")-${driver}/vol1" "incustest-$(basename "${INCUS_DIR}")-${driver}1/vol2"

    # Ensure the target snapshots are not there
    ! incus storage volume snapshot show "incustest-$(basename "${INCUS_DIR}")-${driver}1" vol2/snap0 || false
    ! incus storage volume snapshot show "incustest-$(basename "${INCUS_DIR}")-${driver}1" vol2/snap1 || false

    # Check snapshot volume config was copied
    incus storage volume get "incustest-$(basename "${INCUS_DIR}")-${driver}1" vol2 user.foo | grep -Fx "postsnap1"

    # Copy snapshot to volume
    incus storage volume copy "incustest-$(basename "${INCUS_DIR}")-${driver}/vol1/snap0" "incustest-$(basename "${INCUS_DIR}")-${driver}1/vol3"

    # Check snapshot volume config was copied from snapshot
    incus storage volume show "incustest-$(basename "${INCUS_DIR}")-${driver}1" vol3
    incus storage volume get "incustest-$(basename "${INCUS_DIR}")-${driver}1" vol3 user.foo | grep -Fx "snap0"

    # Rename custom volume using `incus storage volume move`
    incus storage volume move "incustest-$(basename "${INCUS_DIR}")-${driver}1"/vol1 "incustest-$(basename "${INCUS_DIR}")-${driver}1"/vol4
    incus storage volume move "incustest-$(basename "${INCUS_DIR}")-${driver}1"/vol4 "incustest-$(basename "${INCUS_DIR}")-${driver}1"/vol1

    incus storage volume delete "incustest-$(basename "${INCUS_DIR}")-${driver}1" vol1
    incus storage volume delete "incustest-$(basename "${INCUS_DIR}")-${driver}1" vol2
    incus storage volume delete "incustest-$(basename "${INCUS_DIR}")-${driver}1" vol3
    incus storage volume move "incustest-$(basename "${INCUS_DIR}")-${driver}/vol1" "incustest-$(basename "${INCUS_DIR}")-${driver}1/vol1"
    ! incus storage volume show "incustest-$(basename "${INCUS_DIR}")-${driver}" vol1 || false
    incus storage volume show "incustest-$(basename "${INCUS_DIR}")-${driver}1" vol1
    incus storage volume delete "incustest-$(basename "${INCUS_DIR}")-${driver}1" vol1
    incus storage delete "incustest-$(basename "${INCUS_DIR}")-${driver}1"

    for source_driver in "btrfs" "ceph" "cephfs" "dir" "lvm" "zfs"; do
      for target_driver in "btrfs" "ceph" "cephfs" "dir" "lvm" "zfs"; do
        # shellcheck disable=SC2235
        if [ "$source_driver" != "$target_driver" ] \
            && ([ "$incus_backend" = "$source_driver" ] || ([ "$incus_backend" = "ceph" ] && [ "$source_driver" = "cephfs" ] && [ -n "${INCUS_CEPH_CEPHFS:-}" ])) \
            && storage_backend_available "$source_driver" && storage_backend_available "$target_driver"; then
          # source_driver -> target_driver
          incus storage volume create "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol1
          # This will create the snapshot vol1/snap0
          incus storage volume snapshot create "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol1
          # Copy volume with snapshots
          incus storage volume copy "incustest-$(basename "${INCUS_DIR}")-${source_driver}/vol1" "incustest-$(basename "${INCUS_DIR}")-${target_driver}/vol1"
          # Ensure the target snapshot is there
          incus storage volume snapshot show "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol1/snap0
          # Copy volume only
          incus storage volume copy --volume-only "incustest-$(basename "${INCUS_DIR}")-${source_driver}/vol1" "incustest-$(basename "${INCUS_DIR}")-${target_driver}/vol2"
          # Copy snapshot to volume
          incus storage volume copy "incustest-$(basename "${INCUS_DIR}")-${source_driver}/vol1/snap0" "incustest-$(basename "${INCUS_DIR}")-${target_driver}/vol3"
          incus storage volume delete "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol1
          incus storage volume delete "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol2
          incus storage volume delete "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol3
          incus storage volume move "incustest-$(basename "${INCUS_DIR}")-${source_driver}/vol1" "incustest-$(basename "${INCUS_DIR}")-${target_driver}/vol1"
          ! incus storage volume show "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol1 || false
          incus storage volume show "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol1
          incus storage volume delete "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol1

          # target_driver -> source_driver
          incus storage volume create "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol1
          incus storage volume copy "incustest-$(basename "${INCUS_DIR}")-${target_driver}/vol1" "incustest-$(basename "${INCUS_DIR}")-${source_driver}/vol1"
          incus storage volume delete "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol1

          incus storage volume move "incustest-$(basename "${INCUS_DIR}")-${target_driver}/vol1" "incustest-$(basename "${INCUS_DIR}")-${source_driver}/vol1"
          ! incus storage volume show "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol1 || false
          incus storage volume show "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol1
          incus storage volume delete "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol1

          if [ "${source_driver}" = "cephfs" ] || [ "${target_driver}" = "cephfs" ]; then
            continue
          fi

          # create custom block volume without snapshots
          incus storage volume create "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol1 --type=block size=4194304
          incus storage volume copy "incustest-$(basename "${INCUS_DIR}")-${source_driver}/vol1" "incustest-$(basename "${INCUS_DIR}")-${target_driver}/vol1"
          incus storage volume show "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol1 | grep -q 'content_type: block'

          # create custom block volume with a snapshot
          incus storage volume create "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol2 --type=block size=4194304
          incus storage volume snapshot create "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol2
          incus storage volume snapshot show "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol2/snap0 | grep -q 'content_type: block'

          # restore snapshot
          incus storage volume snapshot restore "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol2 snap0
          incus storage volume show "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol2 | grep -q 'content_type: block'

          # copy with snapshots
          incus storage volume copy "incustest-$(basename "${INCUS_DIR}")-${source_driver}/vol2" "incustest-$(basename "${INCUS_DIR}")-${target_driver}/vol2"
          incus storage volume show "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol2 | grep -q 'content_type: block'
          incus storage volume snapshot show "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol2/snap0 | grep -q 'content_type: block'

          # copy without snapshots
          incus storage volume copy "incustest-$(basename "${INCUS_DIR}")-${source_driver}/vol2" "incustest-$(basename "${INCUS_DIR}")-${target_driver}/vol3" --volume-only
          incus storage volume show "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol3 | grep -q 'content_type: block'
          ! incus storage volume snapshot show "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol3/snap0 | grep -q 'content_type: block' || false

          # move images
          incus storage volume move "incustest-$(basename "${INCUS_DIR}")-${source_driver}/vol2" "incustest-$(basename "${INCUS_DIR}")-${target_driver}/vol4"
          ! incus storage volume show "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol2 | grep -q 'content_type: block' || false
          incus storage volume show "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol4 | grep -q 'content_type: block'
          incus storage volume snapshot show "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol4/snap0 | grep -q 'content_type: block'

          # check refreshing volumes

          # create storage volume with user config differing over snapshots
          incus storage volume create "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol5 --type=block size=4194304
          incus storage volume set "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol5 user.foo=snap0vol5
          incus storage volume snapshot create "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol5
          incus storage volume set "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol5 user.foo=snap1vol5
          incus storage volume snapshot create "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol5
          incus storage volume set "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol5 user.foo=snapremovevol5
          incus storage volume snapshot create "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol5 snapremove
          incus storage volume set "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol5 user.foo=postsnap1vol5

          # create storage volume with user config differing over snapshots and additional snapshot than vol5
          incus storage volume create "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol6 --type=block size=4194304
          incus storage volume set "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol6 user.foo=snap0vol6
          incus storage volume snapshot create "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol6
          incus storage volume set "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol6 user.foo=snap1vol6
          incus storage volume snapshot create "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol6
          incus storage volume set "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol6 user.foo=snap2vol6
          incus storage volume snapshot create "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol6
          incus storage volume set "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol6 user.foo=postsnap1vol6

          # copy to new volume destination with refresh flag
          incus storage volume copy --refresh "incustest-$(basename "${INCUS_DIR}")-${source_driver}/vol5" "incustest-$(basename "${INCUS_DIR}")-${target_driver}/vol5"

          # check snapshot volumes (including config) were copied
          incus storage volume get "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol5 user.foo | grep -Fx "postsnap1vol5"
          incus storage volume get "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol5/snap0 user.foo | grep -Fx "snap0vol5"
          incus storage volume get "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol5/snap1 user.foo | grep -Fx "snap1vol5"
          incus storage volume get "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol5/snapremove user.foo | grep -Fx "snapremovevol5"

          # incremental copy to existing volume destination with refresh flag
          incus storage volume copy --refresh "incustest-$(basename "${INCUS_DIR}")-${source_driver}/vol6" "incustest-$(basename "${INCUS_DIR}")-${target_driver}/vol5"

          # check snapshot volumes (including config) was overridden from new source and that missing snapshot is
          # present and that the missing snapshot has been removed.
          # Note: Due to a known issue we are currently only diffing the snapshots by name, so infact existing
          # snapshots of the same name won't be overwritten even if their config or contents is different.
          incus storage volume get "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol5 user.foo | grep -Fx "postsnap1vol5"
          incus storage volume get "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol5/snap0 user.foo | grep -Fx "snap0vol5"
          incus storage volume get "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol5/snap1 user.foo | grep -Fx "snap1vol5"
          incus storage volume get "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol5/snap2 user.foo | grep -Fx "snap2vol6"
          ! incus storage volume get "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol5/snapremove user.foo || false

          # copy ISO custom volumes
          truncate -s 25MiB foo.iso
          incus storage volume import "incustest-$(basename "${INCUS_DIR}")-${source_driver}" ./foo.iso iso1
          incus storage volume copy "incustest-$(basename "${INCUS_DIR}")-${source_driver}"/iso1 "incustest-$(basename "${INCUS_DIR}")-${target_driver}"/iso1
          incus storage volume show "incustest-$(basename "${INCUS_DIR}")-${target_driver}" iso1 | grep -q 'content_type: iso'
          incus storage volume move "incustest-$(basename "${INCUS_DIR}")-${source_driver}"/iso1 "incustest-$(basename "${INCUS_DIR}")-${target_driver}"/iso2
          incus storage volume show "incustest-$(basename "${INCUS_DIR}")-${target_driver}" iso2 | grep -q 'content_type: iso'
          ! incus storage volume show "incustest-$(basename "${INCUS_DIR}")-${source_driver}" iso1 || false

          # clean up
          incus storage volume delete "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol1
          incus storage volume delete "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol1
          incus storage volume delete "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol2
          incus storage volume delete "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol3
          incus storage volume delete "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol4
          incus storage volume delete "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol5
          incus storage volume delete "incustest-$(basename "${INCUS_DIR}")-${target_driver}" vol5
          incus storage volume delete "incustest-$(basename "${INCUS_DIR}")-${source_driver}" vol6
          incus storage volume delete "incustest-$(basename "${INCUS_DIR}")-${target_driver}" iso1
          incus storage volume delete "incustest-$(basename "${INCUS_DIR}")-${target_driver}" iso2
          rm -f foo.iso
        fi
      done
    done
  )

  # shellcheck disable=SC2031,2269
  INCUS_DIR="${INCUS_DIR}"
  kill_incus "${INCUS_STORAGE_DIR}"
}
