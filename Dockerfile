FROM docker:20.10-dind

WORKDIR /app/deps

COPY deps/ /app/deps/

# COPY run.sh /app/

RUN apk add --no-cache dos2unix bash && \
    dos2unix /app/deps/run.sh /app/deps/build.sh && \
    chmod +x /app/deps/run.sh /app/deps/build.sh

VOLUME ["/firmware"]

ENTRYPOINT ["/app/deps/run.sh"]