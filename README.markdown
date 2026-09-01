# Building GnuCash with GTK-OSX #

GnuCash can be built to run more or less natively on OSX -- meaning
without X11. Better yet, the build is almost automatic.

Please see http://wiki.gnucash.org/wiki/MacOSX/Quartz for instructions.

#### Building the dependencies tarball for CI tests ####
The Github Mac runners are Apple Silicon so this must be done on an
Apple Silicon Mac.

The gtk4-macos-dependencies workflow automates the same JHBuild
procedure on the macos-26 Apple Silicon runner. It builds
meta-gnucash-gtk4-dependencies, verifies GTK4, gtk4-macos,
gwengui-gtk4, and AqBanking, assembles the dependency archive, and
then builds and tests the selected GnuCash revision using only the
archive contents. The workflow uploads the archive and its SHA-256
digest as artifacts; publishing it to SourceForge remains a separate
maintainer action.

##### Prerequisites #####
1. Set up [gtk-osx](https://gitlab.gnome.org/GNOME/gtk-osx/README.md)
on your system.
2. Clone this repository.
3. Create a build directory and change its ownership to you:
   ```
   sudo mkdir -p /Users/runner/gnucash/inst
   sudo chown -R <your userid> /Users/runner
   ```
##### Procedure #####
1. Change the file versions in the dependency manifest to match the
   versions in the build you just made. For the GTK4 future branch, use
   `dependencies-gtk4.txt` by setting `DEPS_FILE` when running
   `depstarball.sh`; the default manifest remains `dependencies.txt`.
   Change `GC_VERSION` in `depstarball.sh` to match the current or next
   release as appropriate. If that's not changing consider adding a
   suffix (e.g. 5.13-1) so that the new and old can coexist on
   sourceforge.
2. If you're reusing the build directory from a previous build, clean
   it:
   ```
   rm -rf /Users/runner/gnucash/inst/* /Users/runner/gnucash/build
   /Users/runner/gnucash/src
   ```
2. Build the dependencies:
   ```
   cd /Users/runner
   export PREFIX=/Users/runner/gnucash
   export MODULESET=/Path/to/gnucash-on-osx/modulesets/gnucash.modules
   cp /Path/to/gnucash-on-osx/jhbuildrc-custom ~/.config/jhbuildrc-custom
   jhbuild bootstrap-gtk-osx
   jhbuild build meta-gnucash-dependencies
   ```
   For the GTK4 future branch use:
   ~~~
   jhbuild build meta-gnucash-gtk4-dependencies
   ~~~
3. Start a jhbuild shell:
   ```
    jhbuild shell
   ```
4. Run depstarball.sh. It can be run from any directory. Set
   `DEPS_FILE=dependencies-gtk4.txt` and `VERIFY_GTK4=1` for a GTK4
   archive. If GnuCash compiles and all the tests pass,
   proceed. If not then diagnose the problem, adjust the manifest selected
   by `DEPS_FILE`, and try again.

##### Finish up #####
1. Upload the result to the Dependencies folder in GnuCash's
   Sourceforge project.
2. Change the dependencies file URI in
   `gnucash-git/.github/workflows/macos-tests.yaml` to match the file you
   just made, commit the result, and push it.
3. Commit and push any changes you made to the selected dependency manifest
   and `depstarball.sh`.
