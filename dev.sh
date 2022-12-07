export JEKYLL_VERSION=4
export JEKYLL_NAME=jekyll


if [ -z "$(docker ps -a | grep ${JEKYLL_NAME}-${JEKYLL_VERSION})" ]; then
  docker run --rm \
    --name=${JEKYLL_NAME}-${JEKYLL_VERSION} \
    --volume="$PWD:/srv/jekyll:Z" \
    --volume="$PWD/vendor/bundle:/usr/local/bundle:Z" \
    -p 4000:4000 -p 35729:35729 \
    jekyll/jekyll \
    jekyll serve --livereload --trace --drafts --future
else
  # docker exec -it ${JEKYLL_NAME}-${JEKYLL_VERSION} jekyll serve --livereload --drafts --incremental
  docker stop ${JEKYLL_NAME}-${JEKYLL_VERSION}
  docker start ${JEKYLL_NAME}-${JEKYLL_VERSION}
  docker logs ${JEKYLL_NAME}-${JEKYLL_VERSION} -f
fi



