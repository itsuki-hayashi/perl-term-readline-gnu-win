# Updating bundled Readline

The upstream layout lives under `vendor/readline/`. `vendor/manifest.json`
records its version, URL, archive/file hashes, and ordered local patches.
Installation never downloads sources or uses Git submodules.

1. Download and authenticate the GNU release according to maintainer policy.
   Obtain its trusted SHA-256 digest.
2. Prepare a candidate:

   ```bat
   perl script/update-readline.pl --archive C:\downloads\readline-X.Y.tar.gz --version X.Y --sha256 TRUSTED_DIGEST --url https://ftp.gnu.org/gnu/readline/readline-X.Y.tar.gz
   ```

3. Review the verified candidate under `build/readline-update-*`. The utility
   leaves maintained sources untouched. Audit additions, removals, licenses,
   API changes, and upstream fixes before replacing the vendor tree/manifest.
4. Refresh narrow, ordered patches against the baseline and retain dated
   modification notices. Author-side Git diff tools are acceptable; installation
   must keep using the bundled exact Perl applicator, without fuzz or external patch.
5. Update version configuration, metadata, source/header lists, tests, Changes,
   and license inventory. Do not edit the pristine tree to make a hunk apply.
6. Run clean builds, tests, release checks and archive installs on both native
   architectures. Review behavior and DLL imports before accepting the update.

The same-version import can demonstrate that recorded upstream provenance
reproduces the baseline. Successful compilation alone is not update validation.
