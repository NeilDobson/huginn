docker stop huginn
docker rm huginn
docker run --name huginn -p 3000:3000 -v /silent/huginn/files/mysql:/var/lib/mysql --env-file env  --restart always -d ndarach/huginn
