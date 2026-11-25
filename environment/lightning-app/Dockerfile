# Customer 360 live view. Build context is the `environment/` directory (it also needs the demo-changes code):
#   docker build -f lightning-app/Dockerfile -t c360-live:v1 environment/
#
# It queries the Lightning Table over JDBC: the Confluent JDBC driver is a Java library, so the image carries a JRE and
# the app starts a JVM in-process (JPype). The driver JAR comes from the Confluent Maven repository, checksum-verified.
FROM python:3.12-slim-bookworm
WORKDIR /app
ARG JDBC_VERSION=1.0.0
RUN apt-get update \
 && apt-get install -y --no-install-recommends openjdk-17-jre-headless ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* \
 && ln -s "$(dirname "$(dirname "$(readlink -f "$(which java)")")")" /opt/java \
 && mkdir -p /opt/jdbc \
 && curl -fsSL "https://packages.confluent.io/maven/io/confluent/jdbc/confluent-jdbc/${JDBC_VERSION}/confluent-jdbc-${JDBC_VERSION}.jar" -o "/opt/jdbc/confluent-jdbc-${JDBC_VERSION}.jar" \
 && echo "$(curl -fsSL "https://packages.confluent.io/maven/io/confluent/jdbc/confluent-jdbc/${JDBC_VERSION}/confluent-jdbc-${JDBC_VERSION}.jar.sha1")  /opt/jdbc/confluent-jdbc-${JDBC_VERSION}.jar" | sha1sum -c - \
 && apt-get purge -y curl && apt-get autoremove -y
ENV JAVA_HOME=/opt/java JDBC_JAR=/opt/jdbc/confluent-jdbc-${JDBC_VERSION}.jar
RUN pip install --no-cache-dir "JPype1==1.5.2" "confluent-kafka[avro,schema-registry]==2.6.1" "python-dotenv==1.0.1" "requests==2.32.3" \
 && useradd --create-home --uid 10001 app
COPY lightning-app/server.py /app/server.py
COPY lightning-app/static /app/static
COPY data-generation/producers/config.py data-generation/producers/demo_changes.py /app/data-generation/producers/
COPY data-generation/schemas /app/data-generation/schemas
USER 10001
EXPOSE 8088
CMD ["python", "server.py"]
