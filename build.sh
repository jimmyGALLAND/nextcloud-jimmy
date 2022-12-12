if [ -z "${BASH_SOURCE}" ] ; then
    echo "You need to execute this script using bash v4+ without using pipes"
    exit 1
fi

cd "${BASH_SOURCE%/*}/" || exit 1

NC_VERS=$(curl -s https://api.github.com/repos/nextcloud/server/releases/latest \
| grep "tag_name" \
| cut -d : -f 2 \
| tr -d "\",v " \
)

if [ -z ${NC_VERS} ]; then
 exit 1
fi

if [ ! -f "./version" ]; then
 echo "-" > "./version"
fi

VERS=$(<"./version")
MAJOR_VERS=$( cut -d'.' -f 1  <<< "${NC_VERS}")

if [ ${NC_VERS} != ${VERS} ]; then
 if [[ ${MAJOR_VERS} != 24 && ${MAJOR_VERS} != 25 ]]; then
  exit
 fi

 cd $MAJOR_VERS
 docker build --build-arg NC_VERS=${NC_VERS} --no-cache  -t jimmygalland/nextcloud:latest -t jimmygalland/nextcloud:${NC_VERS} . && \
 docker push jimmygalland/nextcloud:${NC_VERS} && \
 docker push jimmygalland/nextcloud:latest && \
 echo "${NC_VERS}" > "../version"
 cd -

fi

