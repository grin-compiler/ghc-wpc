#!/usr/bin/env bash
# vim: sw=2 et
set -euo pipefail

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

echo 'BUILD_SPHINX_HTML = NO' > mk/validate.mk
echo 'BUILD_SPHINX_PDF = NO' >> mk/validate.mk
hackage_index_state="@1511758800"

cat > mk/build.mk <<EOF
V=1
HADDOCK_DOCS=YES
LATEX_DOCS=YES
HSCOLOUR_SRCS=YES
HSCOLOUR_CMD=/usr/local/bin/HsColour
BUILD_DOCBOOK_HTML=YES
BeConservative=YES
EOF

case "$(uname)" in
  Linux)
    cabal update
    cabal install --reinstall hscolour parsec --index-state=$hackage_index_state

    if [[ -n ${TARGET:-} ]]; then
      if [[ $TARGET = FreeBSD ]]; then
        # cross-compiling to FreeBSD
        echo 'HADDOCK_DOCS = NO' >> mk/build.mk
        echo 'WERROR=' >> mk/build.mk
        # https://circleci.com/docs/2.0/env-vars/#interpolating-environment-variables-to-set-other-environment-variables
        echo 'export PATH=/opt/ghc/bin:$PATH' >> $BASH_ENV
      else
        fail "TARGET=$target not supported"
      fi
#    else
      # assuming Ubuntu
    fi
    ;;
  Darwin)
    if [[ -n ${TARGET:-} ]]; then
      fail "uname=$(uname) not supported for cross-compilation"
    fi
    brew install ghc cabal-install python3 ncurses gmp
    cabal update
    cabal install --reinstall alex happy haddock hscolour --index-state=$hackage_index_state
    # put them on the $PATH, don't fail if already installed
    ln -s $HOME/.cabal/bin/alex /usr/local/bin/alex || true
    ln -s $HOME/.cabal/bin/happy /usr/local/bin/happy || true
    ln -s $HOME/.cabal/bin/hscolour /usr/local/bin/hscolour || true
    ;;
  *)
    fail "uname=$(uname) not supported"
esac
