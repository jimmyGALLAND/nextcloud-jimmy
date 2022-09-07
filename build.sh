NC_VERS=$(curl -s https://api.github.com/repos/nextcloud/server/releases/latest \
| grep "tag_name" \
| cut -d : -f 2 \
| tr -d "\",v " \
)


if [ -z ${NC_VERS} ]; then
	exit 1
fi

docker build --build-arg NC_VERS=${NC_VERS} --no-cache  -t jimmygalland/nextcloud:latest -t jimmygalland/nextcloud:${NC_VERS} . && \
docker push jimmygalland/nextcloud:${NC_VERS} && \
docker push jimmygalland/nextcloud:latest


#docker builder prune -af

#docker login --username jimmygalland
#docker tag [TAG] jimmy.galland/nextcloud:latest
#docker push jimmygalland/nextcloud:latest


