FROM koreader/koandroid@sha256:398dc947aba5116b9cb2290936d9e9727d53723b51603ec3ec347ee11c89d41b
USER root
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends g++ libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxi-dev libxfixes-dev libxss-dev libxtst-dev libwayland-dev libxkbcommon-dev libegl1-mesa-dev libasound2-dev && rm -rf /var/lib/apt/lists/*
