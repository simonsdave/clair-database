#!/usr/bin/env bash
#
# this script automates the process of building a postgress docker
# image that runs postgres and contains a fully populated database
# of current vulnerabilities.

SCRIPT_DIR_NAME="$( cd "$( dirname "$0" )" && pwd )"

VERBOSE=0
TAG="latest"

while true
do
    OPTION=`echo ${1:-} | awk '{print tolower($0)}'`
    case "$OPTION" in
        -v)
            shift
            VERBOSE=1
            ;;
        -t)
            shift
            TAG=${1:-}
            shift
            ;;
        *)
            break
            ;;
    esac
done

if [ $# != 1 ] && [ $# != 3 ]; then
    echo "usage: `basename $0` [-v] [-t <tag>] <dockerhub-username> [<dockerhub-email> <dockerhub-password>]" >&2
    exit 1
fi

DOCKERHUB_USERNAME=${1:-}
DOCKERHUB_EMAIL=${2:-}
DOCKERHUB_PASSWORD=${3:-}

CLAIR_DATABASE_IMAGE_NAME=$DOCKERHUB_USERNAME/clair-database:$TAG
CLAIR_IMAGE_NAME=quay.io/coreos/clair:latest
CLAIR_CONTAINER_NAME=clair

DATABASE_SERVER_DOCKER_IMAGE=postgres:9.5.2

echo "pulling database server docker image $DATABASE_SERVER_DOCKER_IMAGE"

docker pull $DATABASE_SERVER_DOCKER_IMAGE >& /dev/null
if [ $? != 0 ]; then
    echo "error pulling database server docker image $DATABASE_SERVER_DOCKER_IMAGE" >&2
    exit 1
fi

echo "successfully pulled database server docker image"

CLAIR_DATABASE_CONTAINER_NAME=clair-database

echo "starting database server"

docker kill $CLAIR_DATABASE_CONTAINER_NAME >& /dev/null
docker rm $CLAIR_DATABASE_CONTAINER_NAME >& /dev/null

docker \
    run \
    --name $CLAIR_DATABASE_CONTAINER_NAME \
    -e 'PGDATA=/var/lib/postgresql/data-non-volume' \
    -d \
    $DATABASE_SERVER_DOCKER_IMAGE \
    > /dev/null

echo -n "waiting for database server to start "
for i in $(seq 1 10)
do
    docker \
        exec \
        $CLAIR_DATABASE_CONTAINER_NAME \
        sh -c 'echo "\list" | psql -U postgres' \
        >& /dev/null
    if [ $? == 0 ]; then
        break
    fi
    echo -n "."
    sleep 3
done
echo ''

echo "successfully started database server"

echo "creating database"

docker \
    exec \
    $CLAIR_DATABASE_CONTAINER_NAME \
    sh -c 'echo "create database clair" | psql -U postgres' \
    > /dev/null

docker \
    exec \
    $CLAIR_DATABASE_CONTAINER_NAME \
    sh -c 'echo "\list" | psql -U postgres' | \
    grep '^\s*clair' \
    > /dev/null
if [ $? != 0 ]; then
    echo "error creating database" >&2
    exit 1
fi

#
# create clair configuration that will point clair @ the database we just created
#

echo "successfully created database"

CLAIR_CONFIG_DIR=$(mktemp -d 2> /dev/null || mktemp -d -t DAS)
CLAIR_CONFIG_YAML=$CLAIR_CONFIG_DIR/config.yaml

echo "creating clair configuration @ '$CLAIR_CONFIG_YAML'"

curl \
    -s \
    -o "$CLAIR_CONFIG_YAML" \
    -L \
    https://raw.githubusercontent.com/coreos/clair/master/config.example.yaml

# postgres connection string details
# http://www.postgresql.org/docs/9.5/static/libpq-connect.html#LIBPQ-CONNSTRING
sed \
    -i \
    -e 's|source:|source: postgresql://postgres@clair-database:5432/clair?sslmode=disable|g' \
    "$CLAIR_CONFIG_YAML"

echo "created clair configuration"

docker \
    pull \
    $CLAIR_IMAGE_NAME \
    > /dev/null

docker kill $CLAIR_CONTAINER_NAME >& /dev/null
docker rm $CLAIR_CONTAINER_NAME >& /dev/null

docker \
    run \
    -d \
    --name $CLAIR_CONTAINER_NAME \
    -p 6060-6061:6060-6061 \
    --link $CLAIR_DATABASE_CONTAINER_NAME:clair-database \
    -v /tmp:/tmp \
    -v $CLAIR_CONFIG_DIR:/config \
    $CLAIR_IMAGE_NAME \
    -config=/config/config.yaml \
    > /dev/null

echo -n "Waiting for vulnerabilities database update to finish "
while true
do
    docker logs $CLAIR_CONTAINER_NAME | grep "updater: update finished" >& /dev/null
    if [ $? == 0 ]; then
        break
    fi
    echo -n "."
    sleep 15
done
echo ""

docker kill $CLAIR_CONTAINER_NAME > /dev/null
docker rm $CLAIR_CONTAINER_NAME > /dev/null

docker rmi $CLAIR_DATABASE_IMAGE_NAME >& /dev/null

docker \
    commit \
    --change 'ENV PGDATA /var/lib/postgresql/data-non-volume' \
    --change='CMD ["postgres"]' \
    --change='EXPOSE 5432' \
    --change='ENTRYPOINT ["/docker-entrypoint.sh"]' \
    $CLAIR_DATABASE_CONTAINER_NAME \
    $CLAIR_DATABASE_IMAGE_NAME \
    > /dev/null

if [ "$DOCKERHUB_EMAIL" != "" ]; then
    echo "logging in to dockerhub"
    docker login \
        --email="$DOCKERHUB_EMAIL" \
        --username="$DOCKERHUB_USERNAME" \
        --password="$DOCKERHUB_PASSWORD" \
    > /dev/null
    echo "logged in to dockerhub"

    echo "pushing vulnerabilities database ($CLAIR_DATABASE_IMAGE_NAME) to dockerhub"
    docker push $CLAIR_DATABASE_IMAGE_NAME > /dev/null
    echo "pushed vulnerabilities database to dockerhub"
fi

docker kill $CLAIR_DATABASE_CONTAINER_NAME > /dev/null
docker rm $CLAIR_DATABASE_CONTAINER_NAME > /dev/null

echo "done!"

exit 0