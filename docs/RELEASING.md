# Release procedure

The GitHub distribution is named `Term-ReadLine-Gnu` and provides
`Term::ReadLine::Gnu`. Do not upload it to PAUSE: that package belongs to
upstream. Version `1.470_001` sorts above upstream 1.47; a subsequent stable
fork release must be at least 1.471. Update both main-module and XS.pm versions.

1. Review Changes, API documentation, attribution, licenses, and dependency
   provenance. Review the changes since the prior release.
2. Run `perl Makefile.PL`, `nmake`, and `nmake test` against the intended MSVC
   Perl in the matching Native Tools prompt. Inspect optional skips and console logs.
3. In a developer environment run `perl script/release.pl`. It generates META
   files and MANIFEST, runs release checks, and writes a source archive plus
   checksum under `dist/`, using core Perl archive/compression modules.
   `nmake dist` uses the same implementation.
4. Run `perl script/test-archive.pl` to rebuild/test/install a fresh extraction
   and check installed behavior and DLL imports outside the source directory.
   It must build using only the sources and tools included or documented.
5. Inspect archive members. Include source, patches, full vendor code, docs,
   license texts and build helpers. Exclude binaries, local configuration,
   private histories, logs and temporary installation trees.
6. Require green x64 and native ARM64 CI rows; record Perl/toolset/SDK/runner.
   Validate Windows 11 x64 locally until client CI exists. Test optional Tk
   separately if making claims about that integration.
7. Tag reviewed source and attach the tested source archive and checksum to a
   GitHub release only with explicit release authorization. The tooling never
   publishes automatically. State that this replaces upstream in its target
   library tree; users should not install both into the same destination.

Keep corresponding source/build materials with any binary redistribution
according to the applicable GPL conditions; see LICENSING.md. A source-only
GitHub release does not by itself establish a later binary distributor's compliance.
