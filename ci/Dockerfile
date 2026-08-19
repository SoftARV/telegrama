# CI image: Arch plus the GTK/Vala toolchain and TDLib, so CI compiles against the
# same library versions as development rather than Ubuntu's older GTK.
# Rebuilt only when this file changes — see .github/workflows/ci-image.yml.
FROM archlinux:base-devel

# Same commit the AUR telegram-tdlib 1.8.66 package builds, so CI and the dev
# machine run identical TDLib.
ARG TDLIB_REF=a9966eb3704a3351568c28013fed67d797c17828

RUN pacman -Syu --noconfirm --needed \
      git cmake ninja meson pkgconf \
      vala blueprint-compiler \
      glib2 json-glib gtk4 libadwaita libsecret qrencode \
      openssl zlib gperf \
  && pacman -Scc --noconfirm

RUN git clone --filter=blob:none https://github.com/tdlib/td.git /tmp/td \
  && git -C /tmp/td checkout "${TDLIB_REF}" \
  && cmake -S /tmp/td -B /tmp/td/build -G Ninja \
       -DCMAKE_BUILD_TYPE=Release \
       -DCMAKE_INSTALL_PREFIX=/usr \
  && cmake --build /tmp/td/build --target install \
  && rm -rf /tmp/td
