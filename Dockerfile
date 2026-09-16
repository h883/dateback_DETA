FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

ARG FLUTTER_VERSION=stable
ARG ANDROID_SDK_TOOLS_VERSION=11076708
ARG ANDROID_PLATFORM=android-36
ARG ANDROID_BUILD_TOOLS=36.0.0

ENV FLUTTER_HOME=/opt/flutter
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH="${FLUTTER_HOME}/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"
ENV ADB_SERVER_SOCKET=tcp:host.docker.internal:5037

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        clang \
        cmake \
        curl \
        file \
        git \
        gnupg \
        libglu1-mesa \
        libgtk-3-dev \
        liblzma-dev \
        ninja-build \
        openjdk-17-jdk \
        pkg-config \
        unzip \
        wget \
        xz-utils \
        zip \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g firebase-tools

RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "${FLUTTER_HOME}" \
    && flutter config --enable-android --no-analytics \
    && flutter precache --android \
    && git config --global --add safe.directory /workspace

RUN mkdir -p "${ANDROID_HOME}/cmdline-tools" \
    && wget -q "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_TOOLS_VERSION}_latest.zip" -O /tmp/android-tools.zip \
    && unzip -q /tmp/android-tools.zip -d "${ANDROID_HOME}/cmdline-tools" \
    && mv "${ANDROID_HOME}/cmdline-tools/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest" \
    && rm /tmp/android-tools.zip \
    && yes | sdkmanager --licenses >/dev/null \
    && sdkmanager \
        "platform-tools" \
        "platforms;${ANDROID_PLATFORM}" \
        "build-tools;${ANDROID_BUILD_TOOLS}" \
    && yes | flutter doctor --android-licenses >/dev/null \
    && flutter doctor

RUN dart pub global activate flutterfire_cli
ENV PATH="${PATH}:/root/.pub-cache/bin"

WORKDIR /workspace

CMD ["bash"]
