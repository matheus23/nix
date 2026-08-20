#!/usr/bin/env python3

import importlib.util
import sys
from unittest.mock import mock_open, patch


def load_scrubber(path):
    spec = importlib.util.spec_from_file_location("btrfs_snap_scrub", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    scrubber = load_scrubber(sys.argv[1])
    snapshot_path = "/home/.snapshots/952/snapshot/philipp/model.part"
    mounts = """\
/dev/nvme0n1p3 / btrfs rw,subvol=/@,subvolid=256 0 0
/dev/nvme0n1p3 /home btrfs rw,subvol=/@home,subvolid=257 0 0
/dev/backup /backup btrfs rw,subvol=/backup,subvolid=300 0 0
"""

    fsids = {
        snapshot_path: "primary-fsid",
        "/": "primary-fsid",
        "/home": "primary-fsid",
        "/backup": "backup-fsid",
    }

    with (
        patch.object(scrubber, "filesystem_fsid", side_effect=fsids.get),
        patch("builtins.open", mock_open(read_data=mounts)),
    ):
        found = scrubber.btrfs_mounts_for(snapshot_path)

    assert found == [
        ("/", "@", "256"),
        ("/home", "@home", "257"),
    ], found


if __name__ == "__main__":
    main()
