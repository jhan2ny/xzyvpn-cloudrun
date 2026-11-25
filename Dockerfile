ARG XRAY_VERSION=26.9.9
FROM ghcr.io/xtls/xray-core:${XRAY_VERSION} AS core
FROM python:3.13-slim
COPY --from=core /usr/local/bin/xray /usr/local/bin/xray
COPY server.py /app/server.py
ENV PYTHONUNBUFFERED=1
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["python", "/app/server.py"]
