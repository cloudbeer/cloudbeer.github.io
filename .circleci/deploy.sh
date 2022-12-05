git config user.name "$USER_NAME"
git config user.email "$USER_EMAIL"


git checkout -f main
git pull origin main

# find . -maxdepth 1 ! -name '_site' ! -name '.git' ! -name '.gitignore' ! -name '.circleci' -exec rm -rf {} \;

find . -maxdepth 1  ! -name '.'  ! -name '..' ! -name '_site' ! -name '.git' ! -name '.gitignore' ! -name '.circleci' -exec rm -rf {} \;
mv _site/* .
rm -R _site/

echo "-----ls----"
ls -la
echo "--------------------------------"


git add -A .

echo "-----git status----"
git status
echo "--------------------------------"


git commit --allow-empty -m "Page release ${CIRCLE_BUILD_NUM} from ${CIRCLE_BRANCH}"

echo "-----git status----"
git status
# git commit -m "Create new files $(git log source -1 --pretty=%B)"
echo "--------------------------------"

# git remote set-url origin https://cloudbeer:${GITHUB_PWD}@github.com/cloudbeer/cloudbeer.github.io.git
# git push -f origin main
git push --force https://cloudbeer:${GITHUB_PWD}@github.com/cloudbeer/cloudbeer.github.io.git main


echo "deployed successfully"