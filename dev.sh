export JEKYLL_VERSION=4
export JEKYLL_NAME=jekyll

# 如果是 Mac M1 芯片，请使用 cloudbeer/jekyll:4.3.1
# 传统的 X86 用 jekyll/jekyll:4.3.1

if [ -z "$(docker ps -a | grep ${JEKYLL_NAME}-${JEKYLL_VERSION})" ]; then
  docker run \
    --name=${JEKYLL_NAME}-${JEKYLL_VERSION} \
    -v "$PWD:/youbug" \
    -p 4000:4000 -p 35729:35729 \
    cloudbeer/jekyll:4.3.1 \
    sh -c "cd /youbug && bundle install && jekyll serve --livereload --trace --drafts --future --incremental"
else
  docker stop ${JEKYLL_NAME}-${JEKYLL_VERSION}
  docker start ${JEKYLL_NAME}-${JEKYLL_VERSION}
  docker logs ${JEKYLL_NAME}-${JEKYLL_VERSION} -f
fi


    # --volume="$PWD/vendor/bundle:/usr/local/bundle:Z" \

