#!/usr/bin/env python3

import contextlib
import importlib.util
import io
import os
import sys
import tempfile
import uuid
from types import SimpleNamespace
from unittest.mock import MagicMock, call, mock_open, patch


def load_scrubber(path):
    spec = importlib.util.spec_from_file_location("btrfs_snap_scrub", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    scrubber = load_scrubber(sys.argv[1])
    test_mount_discovery(scrubber)
    test_root_mount_matching(scrubber)
    test_missing_path_through_symlink(scrubber)
    test_oldest_snapshot_reference(scrubber)
    test_missing_live_path(scrubber)


def test_mount_discovery(scrubber):
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


def test_root_mount_matching(scrubber):
    root_mount = ("/", "@", "256")
    assert scrubber.mount_of_path("/var/lib/example", [root_mount]) == root_mount


def test_missing_path_through_symlink(scrubber):
    with tempfile.TemporaryDirectory() as temp:
        real = os.path.join(temp, "real")
        link = os.path.join(temp, "link")
        os.mkdir(real)
        os.symlink(real, link)

        assert scrubber.missing_path_probe(os.path.join(link, "missing")) == (
            real,
            os.path.join(real, "missing"),
        )


def test_oldest_snapshot_reference(scrubber):
    root_uuid = uuid.uuid4()
    oldest_uuid = uuid.uuid4()
    subvols = {
        257: root(257, root_uuid, uuid.UUID(int=0), 1),
        700: root(700, uuid.uuid4(), root_uuid, 30),
        800: root(800, oldest_uuid, root_uuid, 10),
        900: root(900, uuid.uuid4(), oldest_uuid, 20),
        600: root(600, uuid.uuid4(), uuid.uuid4(), 5),
    }
    accessible = {
        rootid: "/home/.snapshots/%d/snapshot" % rootid for rootid in subvols
    }
    present = {
        "/home/.snapshots/800/snapshot/philipp/model.part",
        "/home/.snapshots/900/snapshot/philipp/model.part",
        "/home/.snapshots/600/snapshot/philipp/model.part",
    }

    with (
        patch.object(
            scrubber,
            "resolve_accessible",
            side_effect=lambda rootid, _mounts, _list_mount: accessible[rootid],
        ),
        patch.object(scrubber.os.path, "lexists", side_effect=present.__contains__),
    ):
        found = scrubber.find_snapshot_reference(
            "philipp/model.part", 257, subvols, [], "/home"
        )

    assert found == (
        "/home/.snapshots/800/snapshot/philipp/model.part",
        800,
    ), found


def test_missing_live_path(scrubber):
    target = "/home/philipp/model.part"
    snapshot_root = "/home/.snapshots/800/snapshot"
    reference = snapshot_root + "/philipp/model.part"
    root_uuid = uuid.uuid4()
    subvols = [
        root(257, root_uuid, uuid.UUID(int=0), 1),
        root(800, uuid.uuid4(), root_uuid, 10),
    ]

    fake_fs = MagicMock(fd=42)
    fake_fs.subvolumes.return_value = subvols
    file_system = MagicMock()
    file_system.return_value.__enter__.return_value = fake_fs

    real_stat = scrubber.os.stat

    def stat(path, follow_symlinks=False):
        inodes = {"/home/philipp": 100, reference: 200}
        if path in inodes:
            return SimpleNamespace(st_ino=inodes[path])
        return real_stat(path, follow_symlinks=follow_symlinks)

    ino_lookup = MagicMock(
        side_effect=[
            SimpleNamespace(treeid=257, name_bytes=b"philipp/"),
            SimpleNamespace(treeid=800, name_bytes=b"philipp/model.part/"),
        ]
    )
    accessible = {257: "/home", 800: snapshot_root}

    with (
        patch.object(scrubber.os, "geteuid", return_value=0),
        patch.object(
            scrubber.os.path,
            "lexists",
            side_effect=lambda path: path in {"/home/philipp", reference},
        ),
        patch.object(scrubber.os.path, "isfile", side_effect=lambda path: path == reference),
        patch.object(scrubber.os.path, "isdir", return_value=False),
        patch.object(scrubber.os.path, "islink", return_value=False),
        patch.object(scrubber.os, "stat", side_effect=stat),
        patch.object(scrubber, "btrfs_mounts_for", return_value=[("/home", "@home", "257")]),
        patch.object(
            scrubber,
            "resolve_accessible",
            side_effect=lambda rootid, _mounts, _list_mount: accessible[rootid],
        ),
        patch.object(scrubber.btrfs, "FileSystem", file_system),
        patch.object(scrubber.btrfs.ioctl, "ino_lookup", ino_lookup),
        contextlib.redirect_stdout(io.StringIO()) as stdout,
    ):
        result = scrubber.main(["--no-extent-check", target])

    assert result == 0
    output = stdout.getvalue()
    assert "oldest accessible matching snapshot" in output
    assert "Will scrub (1):" in output
    assert snapshot_root in output
    assert call(42, objectid=100) in ino_lookup.call_args_list
    assert call(42, treeid=800, objectid=200) in ino_lookup.call_args_list


def root(rootid, root_uuid, parent_uuid, otransid):
    return SimpleNamespace(
        objectid=rootid,
        uuid=root_uuid,
        parent_uuid=parent_uuid,
        received_uuid=uuid.UUID(int=0),
        otransid=otransid,
        flags=0,
    )


if __name__ == "__main__":
    main()
