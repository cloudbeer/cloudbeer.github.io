git config user.name "$USER_NAME"
git config user.email "$USER_EMAIL"


# find . -maxdepth 1 ! -name '_site' ! -name '.git' ! -name '.gitignore' ! -name '.circleci' -exec rm -rf {} \;

find . -maxdepth 1  ! -name '.'  ! -name '..' ! -name '_site' ! -name '.git' ! -name '.gitignore' ! -name '.circleci' -exec rm -rf {} \;
mv _site/* .
rm -R _site/

git status

# git checkout -f main
# git pull origin main
 
git add .
git commit --allow-empty -m "Page release ${CIRCLE_BUILD_NUM} from ${CIRCLE_BRANCH}"

# git commit -m "Create new files $(git log source -1 --pretty=%B)"


# git remote set-url origin https://cloudbeer:${GITHUB_PWD}@github.com/cloudbeer/cloudbeer.github.io.git
# git push -f origin main
git push -q --force https://cloudbeer:${GITHUB_PWD}@github.com/cloudbeer/cloudbeer.github.io.git main


echo "deployed successfully"