git config user.name "$USER_NAME"
git config user.email "$USER_EMAIL"


git checkout main
git pull origin main

# find . -maxdepth 1 ! -name '_site' ! -name '.git' ! -name '.gitignore' ! -name '.circleci' -exec rm -rf {} \;

find . -maxdepth 1 ! -name '_site' -exec rm -rf {} \;
mv _site/* .
rm -R _site/

git add -fA
git commit -m "Create new files $(git log source -1 --pretty=%B)"


git remote set-url origin https://cloudbeer:${GITHUB_PWD}@github.com/cloudbeer/cloudbeer.github.io.git

git push -f origin main

echo "deployed successfully"