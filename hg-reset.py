#!/usr/bin/env python

# Copyright (c) 2007, 2008 Rocco Rutte <pdmef@gmx.net> and others.
# License: GPLv2

import sys
from binascii import hexlify
from optparse import OptionParser

from hg2git import get_changeset, get_git_sha1, load_cache, setup_repo
from mercurial import node


def heads(ui, repo, start=None, stop=None, max=None):
    # this is copied from mercurial/revlog.py and differs only in
    # accepting a max argument for xrange(startrev+1,...) defaulting
    # to the original repo.changelog.count()
    if start is None:
        start = node.nullid
    if stop is None:
        stop = []
    if max is None:
        max = repo.changelog.count()
    stoprevs = dict.fromkeys([repo.changelog.rev(n) for n in stop])
    startrev = repo.changelog.rev(start)
    reachable = {startrev: 1}
    heads = {startrev: 1}

    parentrevs = repo.changelog.parentrevs
    for r in range(startrev + 1, max):
        for p in parentrevs(r):
            if p in reachable:
                if r not in stoprevs:
                    reachable[r] = 1
                heads[r] = 1
            if p in heads and p not in stoprevs:
                del heads[p]

    return [(repo.changelog.node(r), b"%d" % r) for r in heads]


def get_branches(ui, repo, heads_cache, marks_cache, mapping_cache, max):
    h = heads(ui, repo, max=max)
    stale = dict.fromkeys(heads_cache)
    changed = []
    unchanged = []
    for node, rev in h:  # noqa: F402
        _, _, user, (_, _), _, desc, branch, _ = get_changeset(ui, repo, rev)
        del stale[branch]
        git_sha1 = get_git_sha1(branch)
        cache_sha1 = marks_cache.get(b"%d" % (int(rev) + 1))
        if git_sha1 is not None and git_sha1 is cache_sha1:
            unchanged.append([branch, cache_sha1, rev, desc.split(b"\n")[0], user])
        else:
            changed.append([branch, cache_sha1, rev, desc.split(b"\n")[0], user])
    changed.sort()
    unchanged.sort()
    return stale, changed, unchanged


def get_tags(ui, repo, marks_cache, mapping_cache, max):
    list = repo.tagslist()
    good, bad = [], []
    for tag, node in list:  # noqa: F402
        if tag == b"tip":
            continue
        rev = int(mapping_cache[hexlify(node)])
        cache_sha1 = marks_cache.get(b"%d" % (int(rev) + 1))
        _, _, user, (_, _), _, desc, branch, _ = get_changeset(ui, repo, rev)
        if int(rev) > int(max):
            bad.append([tag, branch, cache_sha1, rev, desc.split(b"\n")[0], user])
        else:
            good.append([tag, branch, cache_sha1, rev, desc.split(b"\n")[0], user])
    good.sort()
    bad.sort()
    return good, bad


def mangle_mark(mark):
    return b"%d" % (int(mark) - 1)


if __name__ == "__main__":

    def bail(parser, opt):
        sys.stderr.write("Error: No option %s given\n" % opt)
        parser.print_help()
        sys.exit(2)

    parser = OptionParser()

    parser.add_option(
        "--marks", dest="marksfile", help="File to read git-fast-import's marks from"
    )
    parser.add_option(
        "--mapping",
        dest="mappingfile",
        help="File to read last run's hg-to-git SHA1 mapping",
    )
    parser.add_option(
        "--heads", dest="headsfile", help="File to read last run's git heads from"
    )
    parser.add_option("--status", dest="statusfile", help="File to read status from")
    parser.add_option("-r", "--repo", dest="repourl", help="URL of repo to import")
    parser.add_option(
        "-R", "--revision", type=int, dest="revision", help="Revision to reset to"
    )

    (options, args) = parser.parse_args()

    if options.marksfile is None:
        bail(parser, "--marks option")
    if options.mappingfile is None:
        bail(parser, "--mapping option")
    if options.headsfile is None:
        bail(parser, "--heads option")
    if options.statusfile is None:
        bail(parser, "--status option")
    if options.repourl is None:
        bail(parser, "--repo option")
    if options.revision is None:
        bail(parser, "-R/--revision")

    heads_cache = load_cache(options.headsfile)
    marks_cache = load_cache(options.marksfile, mangle_mark)
    state_cache = load_cache(options.statusfile)
    mapping_cache = load_cache(options.mappingfile)

    list = int(state_cache.get(b"tip", options.revision))
    if options.revision + 1 > list:  # type: ignore
        sys.stderr.write(
            "Revision is beyond last revision imported: %d>%d\n"
            % (options.revision, list)  # type: ignore
        )
        sys.exit(1)

    ui, repo = setup_repo(options.repourl)

    stale, changed, unchanged = get_branches(
        ui, repo, heads_cache, marks_cache, mapping_cache, options.revision + 1  # type: ignore
    )
    good, bad = get_tags(
        ui, repo, marks_cache, mapping_cache, options.revision + 1  # type: ignore
    )

    print("Possibly stale branches:")
    for branch in stale:
        sys.stdout.write("\t%s\n" % branch.decode("utf8"))

    print("Possibly stale tags:")
    for tag in bad:
        sys.stdout.write(
            "\t%s on %s (r%s)\n"
            % (tag[0].decode("utf8"), tag[1].decode("utf8"), tag[3].decode("utf8"))
        )

    print("Unchanged branches:")
    for branch in unchanged:
        sys.stdout.write(
            "\t%s (r%s)\n" % (branch[0].decode("utf8"), branch[2].decode("utf8"))
        )

    print("Unchanged tags:")
    for tag in good:
        sys.stdout.write(
            "\t%s on %s (r%s)\n"
            % (tag[0].decode("utf8"), tag[1].decode("utf8"), tag[3].decode("utf8"))
        )

    print("Reset branches in '%s' to:" % options.headsfile)
    for branch in changed:
        sys.stdout.write(
            "\t:%s %s\n\t\t(r%s: %s: %s)\n"
            % (
                branch[0].decode("utf8"),
                branch[1].decode("utf8"),
                branch[2].decode("utf8"),
                branch[4].decode("utf8"),
                branch[3].decode("utf8"),
            )
        )

    print("Reset ':tip' in '%s' to '%d'" % (options.statusfile, options.revision))  # type: ignore
