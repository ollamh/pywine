FROM tobix/wine:stable

ENV WINEDEBUG -all
ENV WINEPREFIX /opt/wineprefix

COPY wine-init.sh SHA256SUMS.txt keys.gpg /tmp/helper/
COPY mkuserwineprefix /opt/
COPY opt /opt
ENV PATH $PATH:/opt/bin

# Prepare environment
RUN xvfb-run sh /tmp/helper/wine-init.sh

# renovate: datasource=github-tags depName=python/cpython versioning=pep440
ARG PYTHON_VERSION=3.10.10
# renovate: datasource=github-releases depName=upx/upx versioning=loose
ARG UPX_VERSION=3.96

RUN umask 0 && cd /tmp/helper && \
  curl -LOOO \
    https://www.python.org/ftp/python/${PYTHON_VERSION}/python-${PYTHON_VERSION}-amd64.exe{,.asc} \
    https://github.com/upx/upx/releases/download/v${UPX_VERSION}/upx-${UPX_VERSION}-win64.zip \
  && \
  gpgv --keyring ./keys.gpg python-${PYTHON_VERSION}-amd64.exe.asc python-${PYTHON_VERSION}-amd64.exe && \
  sha256sum -c SHA256SUMS.txt && \
  xvfb-run sh -c "\
    wine python-${PYTHON_VERSION}-amd64.exe /quiet TargetDir=C:\\Python310 \
      Include_doc=0 InstallAllUsers=1 PrependPath=1; \
    wineserver -w" && \
  unzip upx*.zip && \
  mv -v upx*/upx.exe ${WINEPREFIX}/drive_c/windows/ && \
  cd .. && rm -Rf helper

# Install some python software
RUN umask 0 && xvfb-run sh -c "\
  wine pip install --no-warn-script-location pyinstaller; \
  wineserver -w"

# InnoSetup ignores dotfiles if they are considered hidden, so set
# ShowDotFiles=Y. But the registry file is written to disk asynchronously, so
# wait for it to be updated before proceeding
RUN cd $WINEPREFIX && wine reg add 'HKEY_CURRENT_USER\Software\Wine' /v ShowDotFiles /d Y /f && \
while [ ! `grep -Fxq "\"ShowDotFiles\"=\"Y\"" user.reg && echo 1` 1 ]; do sleep 1; done

# Install Inno Setup binaries
RUN umask 0 && cd /tmp/ && \
curl -SL "https://files.jrsoftware.org/is/6/innosetup-6.2.2.exe" -o is.exe && \
xvfb-run sh -c "\
wine is.exe /SP- /VERYSILENT /ALLUSERS /SUPPRESSMSGBOXES /DOWNLOADISCRYPT=1; \
wineserver -w"

# Install unofficial languages
RUN cd "${WINEPREFIX}/drive_c/Program Files (x86)/Inno Setup 6/Languages" && \
curl -L "https://api.github.com/repos/jrsoftware/issrc/tarball/is-6_2_2" \
    | tar xz --strip-components=4 --wildcards "*/Files/Languages/Unofficial/*.isl"

WORKDIR /tmp
